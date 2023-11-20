require_relative "lib/agent_ruby/version"

Gem::Specification.new do |spec|
  spec.name = "agent_ruby"
  spec.version = AgentRuby::VERSION
  spec.authors = ["Matthieu", "Nicolas"]
  spec.email = ["matthv@gmail.com", "nicolasalexandre9@gmail.com"]
  spec.homepage    = "https://www.forestadmin.com"
  spec.summary     = "Ruby agent for Forest Admin."
  spec.description = "Forest is a modern admin interface that works on all major web frameworks. This gem is the main
repository (monorepo) for the Ruby agent."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ForestAdmin/agent-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/ForestAdmin/agent-ruby/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "false"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git Gemfile])
    end
  end

  spec.executables = ["run_rspec"]
  spec.require_paths = ["lib"]
end
