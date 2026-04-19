# module YAML

The YAML module provides serialization and deserialization of YAML
version 1.1 to/from native Crystal data structures, with the additional
independent types specified in http://yaml.org/type/

NOTE: To use `YAML`, you must explicitly import it with `require "yaml"`

### Parsing with `#parse` and `#parse_all`

`YAML.parse` will return an `Any`, which is a convenient wrapper around all possible
YAML core types, making it easy to traverse a complex YAML structure but requires
some casts from time to time, mostly via some method invocations.

```
require "yaml"

data = YAML.parse <<-YAML
         ---
         foo:
           bar:
             baz:
               - qux
               - fox
         YAML
data["foo"]["bar"]["baz"][1].as_s # => "fox"
```

`YAML.parse` can read from an `IO` directly (such as a file) which saves
allocating a string:

```
require "yaml"

yaml = File.open("path/to/file.yml") do |file|
  YAML.parse(file)
end
```

### Parsing with `from_yaml`

A type `T` can be deserialized from YAML by invoking `T.from_yaml(string_or_io)`.
For this to work, `T` must implement
`new(ctx : YAML::PullParser, node : YAML::Nodes::Node)` and decode
a value from the given *node*, using *ctx* to store and retrieve
anchored values (see `YAML::PullParser` for an explanation of this).

Crystal primitive types, `Time`, `Bytes` and `Union` implement
this method. `YAML::Serializable` can be used to implement this method
for user types.

### Dumping with `YAML.dump` or `#to_yaml`

`YAML.dump` generates the YAML representation for an object.
An `IO` can be passed and it will be written there,
otherwise it will be returned as a string. Similarly, `#to_yaml`
(with or without an `IO`) on any object does the same.

For this to work, the type given to `YAML.dump` must implement
`to_yaml(builder : YAML::Nodes::Builder`).

Crystal primitive types, `Time` and `Bytes` implement
this method. `YAML::Serializable` can be used to implement this method
for user types.

```
yaml = YAML.dump({hello: "world"})                               # => "---\nhello: world\n"
File.open("foo.yml", "w") { |f| YAML.dump({hello: "world"}, f) } # writes it to the file
# or:
yaml = {hello: "world"}.to_yaml                               # => "---\nhello: world\n"
File.open("foo.yml", "w") { |f| {hello: "world"}.to_yaml(f) } # writes it to the file
```

## Types

- `YAML::PullParser` (class)

