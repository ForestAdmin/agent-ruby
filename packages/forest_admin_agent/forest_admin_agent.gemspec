lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require_relative "lib/forest_admin_agent/version"

Gem::Specification.new do |spec|
  spec.name         = "forest_admin_agent"
  spec.version      = ForestAdminAgent::VERSION
  spec.authors      = ["Matthieu", "Nicolas"]
  spec.email        = ["matthv@gmail.com", "nicolasalexandre9@gmail.com"]
  spec.homepage     = "https://www.forestadmin.com"
  spec.summary      = "Ruby agent for Forest Admin."
  spec.description  = "Forest is a modern admin interface that works on all major web frameworks. This gem makes Forest
admin work on any Ruby application."
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
        f.start_with?(*%w[bin/ test/ spec/ .git Gemfile LICENSE])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 6.1"
  spec.add_dependency "dry-container", "~> 0.11"
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "filecache", "~> 1.0"
  spec.add_dependency "ipaddress", "~> 0.8.3"
  spec.add_dependency "jsonapi-serializers", "~> 1.0"
  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "ld-eventsource", "~> 2.2"
  spec.add_dependency "mono_logger", "~> 1.1"
  spec.add_dependency "openid_connect", "~> 2.2"
  spec.add_dependency "rake", "~> 13.0"
  spec.add_dependency "rack-cors", "~> 2.0"
  spec.add_dependency "zeitwerk", "~> 2.3"
end
