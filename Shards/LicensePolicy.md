# class Shards::LicensePolicy

## Constants

- `DEFAULT_POLICY_FILENAME` = `".shards-license-policy.yml"`

## Class Methods

### `compute_summary(results : Array(DependencyResult)) : Summary`

### `evaluate(packages : Array(Package), root_spec : Spec, policy : PolicyConfig | Nil, detect : Bool = false) : PolicyReport`

### `evaluate_against_policy(license : String | Nil, policy : PolicyConfig | Nil) : Verdict`

### `load_policy(path : String | Nil) : PolicyConfig | Nil`

## Types

- `Shards::LicensePolicy::DependencyResult` (struct)
- `Shards::LicensePolicy::Override` (struct)
- `Shards::LicensePolicy::PolicyConfig` (struct)
- `Shards::LicensePolicy::PolicyReport` (struct)
- `Shards::LicensePolicy::Summary` (struct)
- `Shards::LicensePolicy::Verdict` (enum)

