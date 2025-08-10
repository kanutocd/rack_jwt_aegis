# frozen_string_literal: true

require_relative 'lib/rack_jwt_aegis/version'

Gem::Specification.new do |spec|
  spec.name = 'rack_jwt_aegis'
  spec.version = RackJwtAegis::VERSION
  spec.authors = ['Ken C. Demanawa']
  spec.email = ['kenneth.c.demanawa@gmail.com']

  spec.summary = 'JWT authentication middleware for multi-tenant Rack applications'
  spec.description = 'JWT authentication middleware with multi-tenant support, company validation, and subdomain isolation.'
  spec.homepage = 'https://github.com/kanutocd/rack_jwt_aegis'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/kanutocd/rack_jwt_aegis'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(['git', 'ls-files', '-z'], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?('.vscode', '.history', 'test', 'adrs', '.ignoreme', 'Gemfile', '.gitignore', '.rspec',
                      'spec/', '.github/')
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'jwt', '~> 2.10'
  spec.add_dependency 'rack', '>= 3.2'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
