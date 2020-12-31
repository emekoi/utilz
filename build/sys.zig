//  Copyright (c) 2020 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");
const builtin = @import("builtin");

const fs = std.fs;
const mem = std.mem;
const path = fs.path;

const ChildProcess = std.ChildProcess;

pub const Package = struct {
    pub const Source = union(enum) {
        pub const Error = fs.Dir.AccessError || mem.Allocator.Error || ChildProcess.SpawnError || error{Git};

        Git: [2][]const u8,
        Local: []const u8,

        pub fn getPath(self: Source, allocator: *mem.Allocator, name: []const u8) Error![]const u8 {
            switch (self) {
                .Local => |file| {
                    try fs.cwd().access(file, .{});
                    return file;
                },
                .Git => |repo| {
                    // the build system is backed by an arena allocator so leaking mem is fine
                    const out = try path.join(allocator, &[_][]const u8{ "deps", repo[1] });
                    fs.cwd().access(out, .{}) catch {
                        if (fs.cwd().access(out, .{})) {} else |_| {
                            var git = try ChildProcess.init(&[_][]const u8{ "git", "clone", repo[0], path.dirname(out).? }, allocator);

                            switch (try git.spawnAndWait()) {
                                ChildProcess.Term{ .Exited = 0 } => try fs.cwd().access(out, .{}),
                                else => return error.Git,
                            }
                        }
                    };
                    return out;
                },
            }
        }
    };

    pub const Type = enum {
        Binary, Library
    };

    name: []const u8,
    source: Source,
    dependencies: ?[]const Package = null,
    kind: Type = .Library,

    pub fn ensureDeps(self: Package, allocator: *mem.Allocator) Source.Error!void {
        _ = try self.source.getPath(allocator, self.name);
        if (self.dependencies) |deps| {
            for (deps) |dep| {
                try dep.ensureDeps(allocator);
            }
        }
    }

    fn addPackages(self: Package, allocator: *mem.Allocator, step: *std.build.LibExeObjStep) !void {
        if (self.dependencies) |deps| {
            for (deps) |dep| {
                step.addPackagePath(dep.name, try dep.source.getPath(allocator, dep.name));
            }
        }
    }

    pub fn build(self: Package, b: *std.build.Builder, target: std.zig.CrossTarget, mode: builtin.Mode) !void {
        try self.ensureDeps(b.allocator);
        const src_path = try self.source.getPath(b.allocator, self.name);

        switch (self.kind) {
            .Binary => {
                const exe = b.addExecutable(self.name, src_path);
                try self.addPackages(b.allocator, exe);
                exe.setBuildMode(mode);
                exe.setTarget(target);
                exe.install();

                const run_cmd = exe.run();
                run_cmd.step.dependOn(b.getInstallStep());
                if (b.args) |args| {
                    run_cmd.addArgs(args);
                }

                const run_step = b.step(self.name, b.fmt("run {}", .{self.name}));
                run_step.dependOn(&run_cmd.step);

                var main_tests = b.addTest(src_path);
                try self.addPackages(b.allocator, main_tests);
                main_tests.setBuildMode(mode);

                const test_name = b.fmt("test-{}", .{self.name});
                const test_step = b.step(test_name, b.fmt("run tests for {}", .{self.name}));
                test_step.dependOn(&main_tests.step);
            },
            .Library => {
                const lib = b.addStaticLibrary(self.name, src_path);
                try self.addPackages(b.allocator, lib);
                lib.setBuildMode(mode);
                lib.install();

                var main_tests = b.addTest(src_path);
                try self.addPackages(b.allocator, main_tests);
                main_tests.setBuildMode(mode);

                const test_name = b.fmt("test-{}", .{self.name});
                const test_step = b.step(test_name, b.fmt("run tests for {}", .{self.name}));
                test_step.dependOn(&main_tests.step);
            },
        }
    }
};
