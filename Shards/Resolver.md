# class Shards::Resolver

## Constructors

### `new(name : String, source : String)`

## Class Methods

### `build(key : String, name : String, source : String)`

### `clear_resolver_cache`

### `find_class(key : String) : Resolver.class | Nil`

### `find_resolver(key : String, name : String, source : String)`

### `normalize_key_source(key : String, source : String)`

### `register_resolver(key, resolver)`

## Instance Methods

### `==(other : Resolver)`

### `available_releases`

### `install_sources(version : Version, install_path : String)`

### `latest_version_for_ref(ref : Ref | Nil) : Version`

### `matches_ref?(ref : Ref, version : Version)`

### `name`

### `parse_requirement(params : Hash(String, String)) : Requirement`

### `read_spec(version : Version) : String | Nil`

### `report_version(version : Version) : String`

### `source`

### `spec(version : Version) : Spec`

### `to_s(io : IO)`

Appends a short String representation of this object
which includes its class name and its object address.

```
class Person
  def initialize(@name : String, @age : Int32)
  end
end

Person.new("John", 32).to_s # => #<Person:0x10a199f20>
```

### `update_local_cache`

### `versions_for(req : Requirement) : Array(Version)`

### `yaml_source_entry`

