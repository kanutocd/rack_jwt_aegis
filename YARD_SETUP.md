# YARD Documentation Setup

This project uses [YARD](https://yardoc.org/) for API documentation generation.

## Available Rake Tasks

### Generate Documentation
```bash
# Generate static HTML documentation
bundle exec rake yard

# Generate documentation and open in browser
bundle exec rake docs
```

### Development Server
```bash
# Start YARD server for live documentation browsing
bundle exec rake docs:server
# Then visit http://localhost:8808
```

### Coverage Reports
```bash
# Check documentation coverage
bundle exec rake docs:coverage
```

## Configuration

The YARD configuration is managed by:

- `.yardopts` - YARD command-line options and file patterns
- `Rakefile` - Rake tasks for documentation generation

## Output

Generated documentation is saved to the `doc/` directory and includes:

- API documentation for all classes and modules
- README, LICENSE, and Code of Conduct
- Architecture documentation from `adrs/architecture.md`
- Cross-referenced method and class documentation
- Search functionality

## Documentation Coverage

Current coverage: **100%** - All classes, modules, methods, and attributes are documented.

## Writing Documentation

Follow YARD documentation standards:

```ruby
# Brief description of the method
#
# @param name [Type] description of parameter
# @param options [Hash] optional parameters
# @option options [String] :key description of option
# @return [ReturnType] description of return value
# @raise [ExceptionType] when this exception is raised
# @example Usage example
#   MyClass.new.method(param)
# @since 1.0.0
def method(name, options = {})
  # implementation
end
```

## Additional Features

- **Grouped Attributes**: Use `@!group` and `@!endgroup` to organize related attributes
- **Cross-references**: YARD automatically links to other classes and methods
- **Markdown Support**: Documentation supports full Markdown syntax
- **Code Examples**: Include working code examples with `@example`