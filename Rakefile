# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
end

# YARD documentation tasks
begin
  require 'yard'
  require 'yard/rake/yardoc_task'

  # Load custom GFM configuration if available
  begin
    require_relative '.yard/yard_gfm_config'
  rescue LoadError
    # GFM config not available, use default markdown processing
  end

  YARD::Rake::YardocTask.new do |t|
    t.files = ['lib/**/*.rb']
    t.options = [
      '--output-dir', 'doc',
      '--readme', 'README.md',
      '--markup-provider', 'kramdown',
      '--markup', 'markdown'
    ]
    t.stats_options = ['--list-undoc']
  end

  desc 'Generate YARD documentation and open in browser'
  task :docs do
    Rake::Task['yard'].invoke
    case RbConfig::CONFIG['host_os']
    when /mswin|mingw|cygwin/
      system 'start doc/index.html'
    when /darwin/
      system 'open doc/index.html'
    when /linux|bsd/
      system 'xdg-open doc/index.html'
    end
  end

  desc 'Run YARD documentation server'
  task 'docs:server' do
    puts 'Starting YARD documentation server at http://localhost:8808'
    puts 'Press Ctrl+C to stop the server'
    system 'yard server --reload --port 8808'
  end

  desc 'Check documentation coverage'
  task 'docs:coverage' do
    puts 'Generating YARD documentation coverage report...'
    system 'yard stats --list-undoc'
  end
rescue LoadError
  puts 'YARD gem is not available. Install it with: gem install yard'

  task :yard do
    abort 'YARD is not available. Install it with: gem install yard'
  end

  task :docs do
    abort 'YARD is not available. Install it with: gem install yard'
  end
end

task default: :test
