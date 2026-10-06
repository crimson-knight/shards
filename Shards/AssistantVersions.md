# module Shards::AssistantVersions

## Constants

- `REMOVED_FILES_KEY` = `"./removed-files.txt"`
- `VERSIONS` = `{{ run("./build_assistant_versions") }}` -- Embedded at compile time by walking src/assistant_versions/

## Class Methods

### `all_versions`

### `current_files`

Build current file state by overlaying all versions oldest-to-newest.
A version's removed-files.txt lists paths that it no longer ships.

### `files_changed_since(since_version : String) : Hash(String, String)`

Get files changed since a given version. Removals are handled by
comparing current_files with the install tracker.

### `latest_version`

