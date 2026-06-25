module Reports
  class PdfRenderer
    def initialize(markdown:)
      @markdown = markdown
    end

    def call
      html = render_html
      Grover.new(
        html,
        format: 'A4',
        display_header_footer: false,
        launch_args: ['--no-sandbox', '--disable-dev-shm-usage'],
        executable_path: ENV.fetch('PUPPETEER_EXECUTABLE_PATH', '/usr/bin/chromium')
      ).to_pdf
    end

    private

    def render_html
      renderer = Redcarpet::Render::HTML.new(hard_wrap: true)
      md = Redcarpet::Markdown.new(renderer, fenced_code_blocks: true, tables: true)
      body = md.render(@markdown)
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>body{font-family:sans-serif;padding:2rem}pre{background:#f4f4f4;padding:1rem;overflow:auto}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.4rem}</style>
        </head><body>#{body}</body></html>
      HTML
    end
  end
end
