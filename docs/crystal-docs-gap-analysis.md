# Crystal Docs Gap Analysis

This fork now treats `crystal docs` as the rendering engine and `shards docs`
as the publishing layer.

That split is intentional. Crystal Docs already does the hard part well:

- parses the codebase
- generates API HTML
- emits `index.json`
- supports core metadata like project name, version, and canonical URLs

For the Ashard release story, we need a little more than raw API docs. We need
publishable documentation that works for humans, agents, and downstream tools.

## What Crystal Docs already provides

- HTML API documentation
- `index.json`
- project metadata flags
- source URL linking
- template support inside the Crystal compiler project

## What Ashard adds today through `shards docs`

- project theme overrides from `docs-theme/style.css`
- AI action buttons in generated HTML pages
- parallel Markdown exports for every generated page
- `llms.txt`
- `llms-full.txt`
- `llms.json`
- published copies of `.claude/` resources and `.mcp.json`
- HTML, Markdown, and JSON indexes for those agent files
- resource links injected back into the generated docs pages
- a repeatable GitHub Pages publishing workflow

## What is still missing from Crystal Docs itself

These are the features that would need to move into Crystal Docs proper if we
ever want the compiler tool to natively own the full publishing story:

1. First-class Markdown output instead of HTML-to-Markdown post-processing
2. First-class machine-readable manifest support beyond `index.json`
3. Built-in `llms.txt` and consolidated text exports
4. A documented extension hook for publishing extra project resources
5. A stable theme override interface that does not require template patching
6. A publish mode for GitHub Pages or static-site deployment targets

## Why we are keeping this in Ashard for now

Keeping these features in `shards docs` has three advantages:

- It preserves compatibility with upstream Crystal Docs behavior
- It lets us move faster on agent-oriented publishing features
- It gives us a clean place to validate which pieces are generally useful
  before proposing them upstream

## Recommended release message

For the Amber v2 and Ashard release notes, the accurate wording is:

> Crystal Docs remains the API documentation engine. Ashard adds the publishing
> layer that turns those docs into a distributable site with Markdown, JSON,
> `llms.txt`, and agent-file exports.
