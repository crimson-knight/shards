# module Shards::Docs::DocsGeneration

## Documentation Generation and Theming

The `shards docs` command wraps `crystal docs` to add theming support,
AI assistant integration buttons, LLM-oriented text exports, and
publishable copies of project agent files.

### Usage

```
shards docs                       # Generate docs with defaults
shards docs --skip-ai-buttons     # No AI buttons
shards docs --skip-agent-files    # Do not copy .claude/.mcp resources
shards docs --skip-llms           # Do not generate llms.txt exports
shards docs -o my_docs            # Custom output directory
```

All standard `crystal docs` options are passed through.

### Theming with CSS Variables

`shards docs` injects CSS custom properties into the generated
stylesheet. To create a custom theme, create `docs-theme/style.css`
in your project root and override the variables:

```css
:root {
  --sidebar-bg: #1a1a2e;
  --sidebar-text: #e0e0e0;
  --accent-primary: #e94560;
  --type-name-color: #e94560;
  --signature-color: #e94560;
  --link-color: #0f3460;
}
```

Available CSS variables cover sidebar colors, main content colors,
code/signature styling, syntax highlighting, and more. See
`Commands::Docs::CSS_VARIABLES` for the full list.

### AI Assistant Buttons

Each generated page includes buttons to discuss the API with:
- **Claude** (claude.ai)
- **ChatGPT** (chatgpt.com)
- **Gemini** (gemini.google.com)
- **View as Markdown** (opens the parallel `.md` file)

The buttons extract page content and construct a prompt that
includes the type name, project name, and documentation.

### Markdown Files

Parallel `.md` files are generated for every HTML page, making
the documentation easily consumable by AI coding assistants,
CLI tools, and any system that prefers plain text.

`shards docs` also emits:
- `llms.txt` — concise machine-oriented index of the generated docs
- `llms-full.txt` — concatenated markdown export of the docs set
- `llms.json` — manifest of markdown and agent resources

If the project contains `.claude/` files or `.mcp.json`, they are copied
into `agent-files/` inside the docs output with HTML/JSON/Markdown indexes
so the published docs site can distribute them directly.

See `Commands::Docs`.

