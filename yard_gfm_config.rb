# frozen_string_literal: true

# Custom YARD configuration for GFM support
begin
  require 'kramdown'
  require 'kramdown-parser-gfm'

  # Simple test to see if GFM is working
  puts 'Testing GFM parsing:'
  test_md = "```ruby\nputs 'hello'\n```"
  result = Kramdown::Document.new(test_md, input: 'GFM').to_html
  puts "Result: #{result}"
rescue LoadError => e
  puts "Warning: Could not load GFM parser: #{e.message}"
end
