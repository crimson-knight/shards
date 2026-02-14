require "json"
require "./command"
require "../helpers"

module Shards
  module Commands
    # Generates project documentation with theming and AI assistant integration.
    #
    # Wraps `crystal docs` and post-processes the output to:
    # - Inject CSS custom properties for theming
    # - Apply project-local theme overrides from `docs-theme/`
    # - Add "Open in AI" buttons (Claude, ChatGPT, Gemini) to each page
    # - Generate parallel Markdown files for AI consumption
    class Docs < Command
      CSS_VARIABLES = <<-CSS
      :root {
        /* Sidebar */
        --sidebar-bg: #2E1052;
        --sidebar-text: #F8F4FD;
        --sidebar-link-hover: #866BA6;
        --sidebar-shadow: rgba(0,0,0,.35);
        --sidebar-input-shadow: rgba(0,0,0,.25);
        --sidebar-input-focus-shadow: rgba(0,0,0,.5);
        --sidebar-focus-outline: #D1B7F1;
        --sidebar-width: 30em;

        /* Project header */
        --project-name-color: #f4f4f4;

        /* Main content */
        --body-bg: #FFFFFF;
        --body-text: #333;
        --body-font: "Avenir", "Tahoma", "Lucida Sans", "Lucida Grande", Verdana, Arial, sans-serif;
        --link-color: #263F6C;
        --link-visited: #112750;
        --heading-color: #444444;

        /* Type name banner */
        --type-name-color: #47266E;
        --type-name-bg: #F8F8F8;
        --type-name-border: #EBEBEB;

        /* Code and signatures */
        --code-font: Menlo, Monaco, Consolas, 'Courier New', Courier, monospace;
        --code-bg: rgba(40,35,30,0.05);
        --pre-bg: #fdfdfd;
        --pre-border: #eee;
        --pre-text: #333;
        --signature-bg: #f8f8f8;
        --signature-color: #47266E;
        --signature-border: #f0f0f0;
        --signature-hover-bg: #D5CAE3;
        --signature-hover-border: #624288;

        /* Accent colors */
        --accent-primary: #47266E;
        --accent-secondary: #624288;
        --accent-highlight: #D5CAE3;
        --kind-color: #866BA6;

        /* Inherited methods */
        --inherited-link: #47266E;
        --inherited-link-hover: #6C518B;
        --inherited-tooltip-bg: #D5CAE3;

        /* Syntax highlighting */
        --syntax-comment: #969896;
        --syntax-number: #0086b3;
        --syntax-type: #0086b3;
        --syntax-string: #183691;
        --syntax-interpolation: #7f5030;
        --syntax-keyword: #a71d5d;
        --syntax-operator: #a71d5d;
        --syntax-method: #795da3;

        /* Borders */
        --h2-border: #E6E6E6;
        --table-border: #eee;

        /* Search results */
        --search-current-border: #ddd;
        --search-current-bg: rgba(200,200,200,0.4);
        --search-args-color: #dddddd;

        /* Permalink */
        --permalink-color: #624288;

        /* AI buttons */
        --ai-btn-bg: #f0f0f0;
        --ai-btn-border: #ddd;
        --ai-btn-text: #555;
        --ai-btn-hover-bg: #e0e0e0;
      }

      @media (prefers-color-scheme: dark) {
        :root {
          --body-bg: #1b1b1b;
          --body-text: white;
          --link-color: #8cb4ff;
          --link-visited: #5f8de3;
          --heading-color: white;
          --type-name-color: white;
          --type-name-bg: #202020;
          --type-name-border: #353535;
          --code-bg: #202020;
          --pre-bg: #202020;
          --pre-border: #353535;
          --pre-text: white;
          --signature-bg: #202020;
          --signature-color: white;
          --signature-border: #353535;
          --signature-hover-bg: #443d4d;
          --signature-hover-border: #b092d4;
          --accent-primary: white;
          --accent-highlight: #443d4d;
          --kind-color: #b092d4;
          --inherited-link: #B290D9;
          --inherited-link-hover: #D4B7F4;
          --inherited-tooltip-bg: #443d4d;
          --syntax-comment: #a1a1a1;
          --syntax-number: #00ade6;
          --syntax-type: #00ade6;
          --syntax-string: #7799ff;
          --syntax-interpolation: #b38668;
          --syntax-keyword: #ff66ae;
          --syntax-operator: #ff66ae;
          --syntax-method: #b9a5d6;
          --h2-border: #353535;
          --table-border: #353535;
          --permalink-color: #b092d4;
          --ai-btn-bg: #2a2a2a;
          --ai-btn-border: #444;
          --ai-btn-text: #ccc;
          --ai-btn-hover-bg: #3a3a3a;
        }
      }
      CSS

      AI_BUTTONS_CSS = <<-CSS
      .ai-assistant-bar {
        display: flex;
        gap: 8px;
        align-items: center;
        margin: 15px 0;
        padding: 10px 0;
        border-top: 1px solid var(--h2-border, #E6E6E6);
        flex-wrap: wrap;
      }
      .ai-assistant-bar .ai-label {
        font-size: 13px;
        color: var(--ai-btn-text, #555);
        margin-right: 4px;
      }
      .ai-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 5px 12px;
        border: 1px solid var(--ai-btn-border, #ddd);
        border-radius: 6px;
        background: var(--ai-btn-bg, #f0f0f0);
        color: var(--ai-btn-text, #555);
        text-decoration: none;
        font-size: 13px;
        cursor: pointer;
        transition: background .15s, border-color .15s;
      }
      .ai-btn:hover {
        background: var(--ai-btn-hover-bg, #e0e0e0);
        border-color: var(--ai-btn-border, #ccc);
      }
      .ai-btn:visited {
        color: var(--ai-btn-text, #555);
      }
      .ai-btn svg {
        width: 16px;
        height: 16px;
        flex-shrink: 0;
      }
      .ai-btn.claude-btn:hover { border-color: #D97706; }
      .ai-btn.chatgpt-btn:hover { border-color: #10A37F; }
      .ai-btn.gemini-btn:hover { border-color: #4285F4; }
      .ai-btn.md-btn:hover { border-color: var(--accent-secondary, #624288); }
      CSS

      AI_BUTTONS_JS = <<-'JS'
      <script>
      (function() {
        function getPageMarkdown() {
          var title = document.querySelector('h1.type-name');
          var content = document.querySelector('.main-content');
          if (!content) return '';

          var text = '';
          if (title) text += '# ' + title.textContent.trim() + '\n\n';

          var sections = content.querySelectorAll('h2, p, pre, dl, .entry-detail');
          sections.forEach(function(el) {
            if (el.tagName === 'H2') text += '## ' + el.textContent.trim() + '\n\n';
            else if (el.tagName === 'P') text += el.textContent.trim() + '\n\n';
            else if (el.tagName === 'PRE') text += '```\n' + el.textContent.trim() + '\n```\n\n';
            else if (el.tagName === 'DL') {
              el.querySelectorAll('dt').forEach(function(dt) {
                text += '- `' + dt.textContent.trim() + '`\n';
              });
              text += '\n';
            }
          });
          return text;
        }

        function buildPrompt(typeName, projectName) {
          return 'I\'m working with the ' + projectName + ' Crystal library. ' +
                 'Help me understand and use `' + typeName + '`. ' +
                 'Here is the API documentation:\n\n';
        }

        function getTypeName() {
          var el = document.querySelector('h1.type-name');
          return el ? el.textContent.trim() : document.title;
        }

        function getProjectName() {
          var el = document.querySelector('.project-name');
          return el ? el.textContent.trim() : 'this project';
        }

        function openInClaude() {
          var prompt = buildPrompt(getTypeName(), getProjectName()) + getPageMarkdown();
          var url = 'https://claude.ai/new?q=' + encodeURIComponent(prompt);
          window.open(url, '_blank');
        }

        function openInChatGPT() {
          var prompt = buildPrompt(getTypeName(), getProjectName()) + getPageMarkdown();
          var url = 'https://chatgpt.com/?q=' + encodeURIComponent(prompt);
          window.open(url, '_blank');
        }

        function openInGemini() {
          var prompt = buildPrompt(getTypeName(), getProjectName()) + getPageMarkdown();
          var url = 'https://gemini.google.com/app?q=' + encodeURIComponent(prompt);
          window.open(url, '_blank');
        }

        function viewMarkdown() {
          var mdPath = window.location.pathname.replace(/\.html$/, '.md');
          if (mdPath === window.location.pathname) mdPath += '.md';
          window.open(mdPath, '_blank');
        }

        document.addEventListener('DOMContentLoaded', function() {
          var h1 = document.querySelector('h1.type-name');
          var mainContent = document.querySelector('.main-content');
          if (!mainContent) return;

          var bar = document.createElement('div');
          bar.className = 'ai-assistant-bar';
          bar.innerHTML =
            '<span class="ai-label">Discuss with AI:</span>' +
            '<button class="ai-btn claude-btn" onclick="window.__openInClaude()" title="Open in Claude">' +
              '<svg viewBox="0 0 24 24" fill="none"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 15h-2v-2h2v2zm2.07-7.75l-.9.92C11.45 10.9 11 11.5 11 13H9v-.5c0-1.1.45-2.1 1.17-2.83l1.24-1.26c.37-.36.59-.86.59-1.41 0-1.1-.9-2-2-2s-2 .9-2 2H6c0-2.21 1.79-4 4-4s4 1.79 4 4c0 .88-.36 1.68-.93 2.25z" fill="currentColor"/></svg>' +
              'Claude' +
            '</button>' +
            '<button class="ai-btn chatgpt-btn" onclick="window.__openInChatGPT()" title="Open in ChatGPT">' +
              '<svg viewBox="0 0 24 24" fill="none"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 17h-2v-2h2v2zm2.07-7.75l-.9.92C13.45 12.9 13 13.5 13 15h-2v-.5c0-1.1.45-2.1 1.17-2.83l1.24-1.26c.37-.36.59-.86.59-1.41 0-1.1-.9-2-2-2s-2 .9-2 2H8c0-2.21 1.79-4 4-4s4 1.79 4 4c0 .88-.36 1.68-.93 2.25z" fill="currentColor"/></svg>' +
              'ChatGPT' +
            '</button>' +
            '<button class="ai-btn gemini-btn" onclick="window.__openInGemini()" title="Open in Gemini">' +
              '<svg viewBox="0 0 24 24" fill="none"><path d="M12 2L2 7v10l10 5 10-5V7L12 2zm0 2.18L19.18 8 12 11.82 4.82 8 12 4.18zM4 9.12l7 3.5V19.5l-7-3.5V9.12zm9 10.38v-6.88l7-3.5v6.88l-7 3.5z" fill="currentColor"/></svg>' +
              'Gemini' +
            '</button>' +
            '<button class="ai-btn md-btn" onclick="window.__viewMarkdown()" title="View as Markdown">' +
              '<svg viewBox="0 0 24 24" fill="none"><path d="M20.56 18H3.44C2.65 18 2 17.37 2 16.59V7.41C2 6.63 2.65 6 3.44 6h17.12c.79 0 1.44.63 1.44 1.41v9.18c0 .78-.65 1.41-1.44 1.41zM6.81 15.19v-3.68l1.83 2.29 1.83-2.29v3.68h1.83V8.81h-1.83l-1.83 2.29-1.83-2.29H5v6.38h1.81zm10.99-3.19h-1.83V8.81h-1.83V12h-1.84l2.75 3.19L17.8 12z" fill="currentColor"/></svg>' +
              'Markdown' +
            '</button>';

          if (h1 && h1.nextSibling) {
            mainContent.insertBefore(bar, h1.nextSibling);
          } else {
            mainContent.insertBefore(bar, mainContent.firstChild);
          }
        });

        window.__openInClaude = openInClaude;
        window.__openInChatGPT = openInChatGPT;
        window.__openInGemini = openInGemini;
        window.__viewMarkdown = viewMarkdown;
      })();
      </script>
      JS

      def run(args : Array(String))
        output_dir = "docs"
        skip_ai_buttons = false
        crystal_args = [] of String

        args.each do |arg|
          case arg
          when "--output", "-o"
            # handled by next arg via crystal docs passthrough
            crystal_args << arg
          when "--skip-ai-buttons"
            skip_ai_buttons = true
          else
            if crystal_args.last? == "--output" || crystal_args.last? == "-o"
              output_dir = arg
            end
            crystal_args << arg
          end
        end

        # Run crystal docs
        Log.info { "Generating documentation..." }
        crystal_args_str = crystal_args.empty? ? "" : " " + crystal_args.join(" ")
        status = Process.run(
          "#{Shards.crystal_bin} docs#{crystal_args_str}",
          shell: true,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )

        unless status.success?
          raise Error.new("crystal docs failed")
        end

        # Post-process: inject CSS variables and theme
        inject_theme(output_dir)

        # Post-process: inject AI buttons
        unless skip_ai_buttons
          inject_ai_buttons(output_dir)
        end

        # Generate markdown files from HTML
        generate_markdown_files(output_dir)

        Log.info { "Documentation generated in #{output_dir}/" }
      end

      private def inject_theme(output_dir : String)
        css_path = File.join(output_dir, "css", "style.css")
        return unless File.exists?(css_path)

        original_css = File.read(css_path)

        themed_css = String.build do |str|
          # Prepend CSS variables
          str << CSS_VARIABLES
          str << "\n\n"
          str << original_css
          str << "\n\n"
          str << AI_BUTTONS_CSS

          # Append project theme override if it exists
          theme_path = File.join(path, "docs-theme", "style.css")
          if File.exists?(theme_path)
            str << "\n\n/* Project theme override */\n"
            str << File.read(theme_path)
            Log.info { "Applied project theme from docs-theme/style.css" }
          end
        end

        File.write(css_path, themed_css)
      end

      private def inject_ai_buttons(output_dir : String)
        Dir.glob(File.join(output_dir, "**", "*.html")).each do |html_path|
          content = File.read(html_path)

          # Inject the AI buttons JS before </body>
          if content.includes?("</body>")
            content = content.sub("</body>", "#{AI_BUTTONS_JS}\n</body>")
            File.write(html_path, content)
          end
        end
      end

      private def generate_markdown_files(output_dir : String)
        # Read the JSON index for type info
        json_path = File.join(output_dir, "index.json")
        return unless File.exists?(json_path)

        begin
          index = JSON.parse(File.read(json_path))
        rescue
          Log.warn { "Could not parse index.json for markdown generation" }
          return
        end

        project_name = index["repository_name"]?.try(&.as_s?) || "project"

        # Generate markdown for each HTML file from its content
        Dir.glob(File.join(output_dir, "**", "*.html")).each do |html_path|
          # Skip non-type pages
          basename = File.basename(html_path, ".html")
          next if basename == "404"

          md_path = html_path.sub(/\.html$/, ".md")
          markdown = html_to_markdown(html_path, project_name)
          File.write(md_path, markdown) unless markdown.empty?
        end

        # Generate markdown from program types in JSON
        if program = index["program"]?
          generate_type_markdown(program, output_dir, project_name)
        end

        md_count = Dir.glob(File.join(output_dir, "**", "*.md")).size
        Log.info { "Generated #{md_count} markdown files for AI consumption" }
      end

      private def generate_type_markdown(type_json : JSON::Any, output_dir : String, project_name : String)
        return unless type_json.as_h?

        # Process subtypes recursively
        if types = type_json["types"]?.try(&.as_a?)
          types.each do |subtype|
            if path = subtype["path"]?.try(&.as_s?)
              md_path = File.join(output_dir, path.sub(/\.html$/, ".md"))
              Dir.mkdir_p(File.dirname(md_path))

              markdown = type_json_to_markdown(subtype, project_name)
              File.write(md_path, markdown) unless markdown.empty?

              generate_type_markdown(subtype, output_dir, project_name)
            end
          end
        end
      end

      private def type_json_to_markdown(type_json : JSON::Any, project_name : String) : String
        String.build do |md|
          full_name = type_json["full_name"]?.try(&.as_s?) || "Unknown"
          kind = type_json["kind"]?.try(&.as_s?) || "type"

          md << "# #{kind} #{full_name}\n\n"

          # Doc comment (raw markdown from source)
          if doc = type_json["doc"]?.try(&.as_s?)
            md << doc << "\n\n"
          end

          # Constants
          if constants = type_json["constants"]?.try(&.as_a?)
            unless constants.empty?
              md << "## Constants\n\n"
              constants.each do |c|
                name = c["name"]?.try(&.as_s?) || ""
                value = c["value"]?.try(&.as_s?) || ""
                md << "- `#{name}` = `#{value}`"
                if cdoc = c["doc"]?.try(&.as_s?)
                  md << " -- " << cdoc.lines.first
                end
                md << "\n"
              end
              md << "\n"
            end
          end

          # Methods
          {"constructors" => "Constructors",
           "class_methods" => "Class Methods",
           "instance_methods" => "Instance Methods",
           "macros" => "Macros"}.each do |field, title|
            if methods = type_json[field]?.try(&.as_a?)
              unless methods.empty?
                md << "## #{title}\n\n"
                methods.each do |m|
                  name = m["name"]?.try(&.as_s?) || ""
                  html_id = m["html_id"]?.try(&.as_s?) || ""
                  args_str = m["args_string"]?.try(&.as_s?) || ""
                  md << "### `#{name}#{args_str}`\n\n"
                  if mdoc = m["doc"]?.try(&.as_s?)
                    md << mdoc << "\n\n"
                  end
                end
              end
            end
          end

          # Subtypes listing
          if types = type_json["types"]?.try(&.as_a?)
            unless types.empty?
              md << "## Types\n\n"
              types.each do |t|
                tname = t["full_name"]?.try(&.as_s?) || ""
                tkind = t["kind"]?.try(&.as_s?) || ""
                md << "- `#{tname}` (#{tkind})\n"
              end
              md << "\n"
            end
          end
        end
      end

      private def html_to_markdown(html_path : String, project_name : String) : String
        content = File.read(html_path)
        basename = File.basename(html_path, ".html")

        String.build do |md|
          # Extract title
          if content =~ /<title>([^<]+)<\/title>/
            md << "# #{$1}\n\n"
          elsif basename == "index"
            md << "# #{project_name}\n\n"
          else
            md << "# #{basename}\n\n"
          end

          # Extract main content body text (strip HTML tags for simple conversion)
          if content =~ /<div class="main-content">(.*?)<\/body>/m
            body = $1
            # Strip script tags
            body = body.gsub(/<script[^>]*>.*?<\/script>/m, "")
            # Convert headers
            body = body.gsub(/<h([1-6])[^>]*>(.*?)<\/h\1>/m) { "#{"#" * $1.to_i} #{strip_tags($2)}\n\n" }
            # Convert code blocks
            body = body.gsub(/<pre[^>]*><code[^>]*>(.*?)<\/code><\/pre>/m) { "```\n#{html_decode(strip_tags($1))}\n```\n\n" }
            body = body.gsub(/<pre[^>]*>(.*?)<\/pre>/m) { "```\n#{html_decode(strip_tags($1))}\n```\n\n" }
            # Convert inline code
            body = body.gsub(/<code[^>]*>(.*?)<\/code>/m) { "`#{strip_tags($1)}`" }
            # Convert links
            body = body.gsub(/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/m) { "[#{strip_tags($2)}](#{$1})" }
            # Convert paragraphs
            body = body.gsub(/<p[^>]*>(.*?)<\/p>/m) { "#{strip_tags($1)}\n\n" }
            # Convert list items
            body = body.gsub(/<li[^>]*>(.*?)<\/li>/m) { "- #{strip_tags($1)}\n" }
            # Strip remaining tags
            body = strip_tags(body)
            # Normalize whitespace
            body = body.gsub(/\n{3,}/, "\n\n").strip

            md << body
          end
        end
      end

      private def strip_tags(html : String) : String
        html.gsub(/<[^>]+>/, "")
      end

      private def html_decode(text : String) : String
        text.gsub("&amp;", "&")
            .gsub("&lt;", "<")
            .gsub("&gt;", ">")
            .gsub("&quot;", "\"")
            .gsub("&#39;", "'")
      end
    end
  end
end
