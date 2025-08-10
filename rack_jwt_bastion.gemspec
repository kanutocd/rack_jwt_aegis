# frozen_string_literal: true

require_relative "lib/rack_jwt_bastion/version"

Gem::Specification.new do |spec|
  spec.name = "rack_jwt_bastion"
  spec.version = RackJwtBastion::VERSION
  spec.authors = ["Ken C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "JWT authentication middleware for multi-tenant Rack applications"
  spec.description = "JWT authentication middleware with multi-tenant support, company validation, and subdomain isolation."
  spec.homepage = "https://github.com/kendemanawa/rack_jwt_bastion"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kendemanawa/rack_jwt_bastion"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ .vscode .history test adrs .ignoreme Gemfile .gitignore .rspec spec/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]


  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 2.7"
  spec.add_development_dependency "vcr", "~> 6.3"
  spec.add_development_dependency "rubocop", "~> 1.79"
  spec.add_development_dependency "rubocop-minitest", "~> 0.38.1"
  spec.add_development_dependency "rubocop-performance", "~> 1.25"
  spec.add_development_dependency "rubocop-rake", "~> 0.7.1"
  spec.add_development_dependency "simplecov", "~> 0.22.0"
  spec.add_development_dependency "rake", "~> 13.3"
  spec.add_development_dependency "irb", "~> 1.15"
  spec.add_development_dependency "yard", "~> 0.9.37"
  spec.add_development_dependency "kramdown", "~> 2.5"

  # Runtime dependencies
  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "rack", ">= 2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
