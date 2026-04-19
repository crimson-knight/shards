# module Shards::AssistantVersions

## Constants

- `VERSIONS` = `{{ run("./build_assistant_versions") }}` -- Embedded at compile time by walking src/assistant_versions/

## Class Methods

### `all_versions`

### `current_files`

Build current file state by overlaying all versions oldest-to-newest

### `files_changed_since(since_version : String) : Hash(String, String)`

Get only files that changed since a given version

### `latest_version`

