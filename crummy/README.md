<h1 align="center">crummy</h1>

a crummy parser for a INI/TOML like configuration language.

## spec
```toml
[section]
key = value
duplicate = $section.key
dotted.key = "string value"

[section.subsection]
; arrays can be heterogeneous but this may change later on
array = [
  "string",
  'raw string', 
  0xff_ff_ff, ; supports base 16, 10, 8, and 2

]

```