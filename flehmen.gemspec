# frozen_string_literal: true

require_relative "lib/flehmen/version"

Gem::Specification.new do |spec|
  spec.name          = "flehmen"
  spec.version       = Flehmen::VERSION
  spec.authors       = ["ryosk7"]
  spec.summary       = "MCP server gem that exposes Rails ActiveRecord models to Claude Desktop"
  spec.description   = "A generic Ruby gem that auto-discovers ActiveRecord models and provides " \
                       "read-only query tools via the Model Context Protocol (MCP) for Claude Desktop integration."
  spec.license       = "MIT"
  spec.homepage      = "https://github.com/ryosk7/flehmen"

  spec.required_ruby_version = ">= 3.1.0"

  spec.add_dependency "fast-mcp", "~> 1.5"
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "railties", ">= 7.0"

  spec.executables   = ["flehmen"]
  spec.bindir        = "bin"
  spec.files         = Dir["lib/**/*", "bin/*", "LICENSE.txt", "README.md"]
end
