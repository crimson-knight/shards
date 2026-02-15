# demo_analytics

A Crystal analytics library that provides simple metric querying.

## Usage

```crystal
require "demo_analytics"

result = DemoAnalytics.query("page_views")
puts result # => "page_views=42831 (+12.5% wow)"
```

## Available Metrics

- `page_views` — Page view counts with week-over-week change
- `users` — Active users and session counts
- `events` — Total and unique event counts
- Any other string returns sample data

## MCP Server

This shard ships an MCP server (`query-tool`) that exposes `query_analytics`
as a tool. After `shards install`, use `shards mcp start` to launch it.
