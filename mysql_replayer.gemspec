# frozen_string_literal: true

require_relative "lib/mysql_replayer/version"

Gem::Specification.new do |spec|
  spec.name          = "mysql_replayer"
  spec.version       = MysqlReplayer::VERSION
  spec.authors       = ["Andrew Stephenson"]
  spec.email         = ["Andrew.Stephenson123@gmail.com"]

  spec.summary       = "MySQL Query Log Replayer"
  spec.description   = "Given a MySQL query log, replay the queries in it against another DB."
  spec.homepage      = "https://github.com/andrewls/mysql-replayer"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/andrewls/mysql-replayer"
  spec.metadata["changelog_uri"] = "https://github.com/andrewls/mysql-replayer/blob/main/changelog.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'pry'

  spec.add_dependency 'activesupport'
  spec.add_dependency 'fast_blank'
  spec.add_dependency 'mysql2'
  spec.add_dependency 'colorize'
  spec.add_dependency 'oj'

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
