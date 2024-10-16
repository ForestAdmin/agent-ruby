require_relative "lib/forest_admin_rails/version"

Gem::Specification.new do |spec|
  spec.name        = "forest_admin_rails"
  spec.version     = ForestAdminRails::VERSION
  spec.authors     = ["Matthieu", "Nicolas"]
  spec.email       = ["matthv@gmail.com", "nicolasalexandre9@gmail.com"]
  spec.homepage    = "https://www.forestadmin.com"
  spec.summary     = "Official Rails Agent for Forest Admin."
  spec.description = "Forest is a modern admin interface that works on all major web frameworks. This gem makes Forest
admin work on any Rails application (Rails >= 6.1)."
  spec.license     = "GPL-3.0"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ForestAdmin/agent-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/ForestAdmin/agent-ruby/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'false'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,lib}/**/*", "LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "dry-configurable", "~> 1.1"
  spec.add_dependency "rails", ">= 6.1"
  spec.add_dependency "zeitwerk", "~> 2.3"
end
