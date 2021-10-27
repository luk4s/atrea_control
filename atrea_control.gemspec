# frozen_string_literal: true

require_relative "lib/atrea_control/version"

Gem::Specification.new do |spec|
  spec.name          = "atrea_control"
  spec.version       = AtreaControl::VERSION
  spec.authors       = ["Lukáš Pokorný"]
  spec.email         = ["pokorny@luk4s.cz"]

  spec.summary       = "Get data control.atrea.eu"
  spec.description   = "Read data from web controller of RD5 duplex by Atrea."
  spec.homepage      = "https://github.com/luk4s/atrea_control"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.2")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/luk4s/atrea_control"
  spec.metadata["changelog_uri"] = "https://github.com/luk4s/atrea_control/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html

  spec.add_dependency "nokogiri", "~> 1.12"
  spec.add_dependency "rest-client", "~> 2.1"
  spec.add_dependency "selenium-webdriver", "~> 3.142"
end
