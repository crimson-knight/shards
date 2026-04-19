# module Shards::Compliance::HtmlTemplate

## Constants

- `CSS` = `"  * { box-sizing: border-box; margin: 0; padding: 0; }\n  body { font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif; max-width: 1200px; margin: 0 auto; padding: 2rem; color: #333; }\n  header { border-bottom: 2px solid #e0e0e0; padding-bottom: 1rem; margin-bottom: 2rem; }\n  h1 { font-size: 1.8rem; color: #1a1a2e; }\n  h2 { font-size: 1.3rem; margin: 1.5rem 0 1rem; color: #16213e; cursor: pointer; }\n  .report-meta { display: flex; gap: 2rem; margin-top: 0.5rem; color: #666; font-size: 0.9rem; }\n  .status-badge { display: inline-block; padding: 0.4rem 1rem; border-radius: 4px; font-weight: bold; color: white; text-transform: uppercase; }\n  .status-badge.pass { background: #28a745; }\n  .status-badge.fail { background: #dc3545; }\n  .status-badge.action_required { background: #ffc107; color: #333; }\n  table { width: 100%; border-collapse: collapse; margin: 1rem 0; }\n  th, td { text-align: left; padding: 0.5rem 0.75rem; border-bottom: 1px solid #e0e0e0; }\n  th { background: #f8f9fa; font-weight: 600; }\n  tr.pass td:nth-child(3) { color: #28a745; }\n  tr.warn td:nth-child(3) { color: #ffc107; }\n  .summary { margin-bottom: 2rem; }\n  .metrics { max-width: 400px; }\n  section { margin-bottom: 2rem; }\n  .section-content { margin-left: 1rem; }\n  .attestation { border-top: 2px solid #e0e0e0; padding-top: 1rem; }\n  footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid #e0e0e0; color: #999; font-size: 0.85rem; }\n  @media print { .section-header { cursor: default; } body { max-width: none; } }"`
- `JS` = `"  document.querySelectorAll('.section-header').forEach(function(h) {\n    h.addEventListener('click', function() {\n      var content = h.nextElementSibling;\n      if (content) { content.style.display = content.style.display === 'none' ? '' : 'none'; }\n    });\n  });"`

## Class Methods

### `render(data : ReportData) : String`

