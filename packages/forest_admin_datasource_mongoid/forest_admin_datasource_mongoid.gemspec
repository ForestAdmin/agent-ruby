lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require_relative "lib/forest_admin_datasource_mongoid/version"

Gem::Specification.new do |spec|
  spec.name = "forest_admin_datasource_mongoid"
  spec.version = ForestAdminDatasourceMongoid::VERSION
  spec.authors      = ["Matthieu", "Nicolas"]
  spec.email        = ["matthv@gmail.com", "nicolasalexandre9@gmail.com"]
  spec.homepage     = "https://www.forestadmin.com"
  spec.summary      = "Ruby agent for Forest Admin."
  spec.description  = "Forest is a modern admin interface that works on all major web frameworks. This gem makes Forest
admin work on any Ruby application."
  spec.license = "GPL-3.0"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ForestAdmin/agent-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/ForestAdmin/agent-ruby/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "false"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "mongoid", ">= 9.0"
  spec.add_dependency "activesupport", ">= 6.1"
  spec.add_dependency "base64"
  spec.add_dependency "benchmark"
  spec.add_dependency "bigdecimal"
  spec.add_dependency "cgi"
  spec.add_dependency "csv"
  spec.add_dependency "logger"
  spec.add_dependency "mutex_m"
  spec.add_dependency "ostruct"
  spec.add_dependency "zeitwerk", "~> 2.3"
end
