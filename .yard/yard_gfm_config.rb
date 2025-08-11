# frozen_string_literal: true

# Custom YARD configuration for GitHub Flavored Markdown support
#
# This configuration ensures the kramdown-parser-gfm gem is available for
# proper rendering of fenced code blocks (```language) in YARD documentation.
#
# The actual GFM parsing integration is handled by YARD when kramdown is
# configured with the GFM input parser.

begin
  require 'kramdown'
  require 'kramdown-parser-gfm'
  
  # Ensure GFM parser is available - YARD will use it automatically
  # when kramdown processes markdown with input: 'GFM'
  
rescue LoadError => e
  # Fallback gracefully if GFM parser is not available
  puts "Warning: kramdown-parser-gfm not available, fenced code blocks may not render properly: #{e.message}"
end
