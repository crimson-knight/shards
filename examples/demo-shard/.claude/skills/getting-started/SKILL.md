---
name: getting-started
description: How to install and use the demo_analytics Crystal library
user-invocable: true
---

# Getting Started with demo_analytics

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  demo_analytics:
    github: example/demo_analytics
```

Then run `shards install`.

## Basic Usage

```crystal
require "demo_analytics"

# Query a specific metric
puts DemoAnalytics.query("page_views")
puts DemoAnalytics.query("users")
puts DemoAnalytics.query("events")
```

## MCP Server

After installing, start the MCP server:

```sh
shards mcp start demo_analytics/query-tool
```

This makes the `query_analytics` tool available to Claude Code and other
MCP-compatible AI assistants.
