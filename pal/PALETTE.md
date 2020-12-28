# palette file spec
palettes can passed to pal as `palette-profile` where no `-profile` means to use the `default` profile. 
```toml
# the only required profile
[default]
foreground = '#rrggbb'
background = '#rrggbb'
cursor = '#rrggbb'
colors = [
  '#rrggbb', # color 1
  '#rrggbb', # color 2
  # '#rrggbb'...
  '#rrggbb', # color 16
]

[light]
foreground = '#rrggbb'
background = '#rrggbb'
cursor = '#rrggbb'
colors = [
  # '#rrggbb'...
]

[dark]
foreground = '#rrggbb'
background = '#rrggbb'
cursor = '#rrggbb'
colors = [
  # '#rrggbb'...
]

[random-profile-name]
foreground = '#rrggbb'
background = '#rrggbb'
cursor = '#rrggbb'
colors = [
  # '#rrggbb'...
]
```

