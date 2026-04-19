# class Shards::MolinilloSolver

## Constructors

### `new(spec : Spec, override : Override | Nil = nil, *, prereleases : Bool = false)`

## Class Methods

### `crystal_version_req(specification : Shards::Spec)`

## Instance Methods

### `after_resolution`

Called after resolution ends (either successfully or with an error).
By default, prints a newline.

@return [void]

### `apply_overrides(deps : Array(Dependency))`

### `before_resolution`

Called before resolution begins.

@return [void]

### `dependencies_for(specification : S) : Array(R)`

Returns the dependencies of `specification`.
@note This method should be 'pure', i.e. the return value should depend
  only on the `specification` parameter.

@param [Object] specification
@return [Array<Object>] the dependencies that are required by the given
  `specification`.

### `indicate_progress`

Called roughly every {#progress_rate}, this method should convey progress
to the user.

@return [void]

### `locks=(locks : Array(Package) | Nil)`

### `name_for(spec : Shards::Spec)`

### `name_for(dependency : Shards::Dependency)`

Returns the name for the given `dependency`.
@note This method should be 'pure', i.e. the return value should depend
  only on the `dependency` parameter.

@param [Object] dependency
@return [String] the name for the given `dependency`.

### `name_for_explicit_dependency_source`

@return [String] the name of the source of explicit dependencies, i.e.
  those passed to {Resolver#resolve} directly.

### `name_for_locking_dependency_source`

@return [String] the name of the source of 'locked' dependencies, i.e.
  those passed to {Resolver#resolve} directly as the `base`

### `on_override(dependency : Dependency | Shards::Spec) : Dependency | Nil`

### `prepare(development : Bool | Nil = true)`

### `requirement_satisfied_by?(dependency, activated, spec)`

### `search_for(dependency : R) : Array(S)`

Search for the specifications that match the given dependency.
The specifications in the returned array will be considered in reverse
order, so the latest version ought to be last.
@note This method should be 'pure', i.e. the return value should depend
  only on the `dependency` parameter.

@param [Object] dependency
@return [Array<Object>] the specifications that satisfy the given
  `dependency`.

### `solve`

