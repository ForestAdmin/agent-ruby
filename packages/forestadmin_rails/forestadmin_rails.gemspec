require_relative "lib/forestadmin_rails/version"

Gem::Specification.new do |spec|
  spec.name        = "forestadmin_rails"
  spec.version     = ForestadminRails::VERSION
  spec.authors     = ["Matthieu", "Nicolas"]
  spec.email       = ["matthv@gmail.com", "nicolasalexandre9@gmail.com"]
  spec.homepage    = "https://www.forestadmin.com"
  spec.summary     = "Official Rails Agent for Forest Admin."
  spec.description = "Forest is a modern admin interface that works on all major web frameworks. This gem makes Forest
admin work on any Rails application (Rails >= 6.1)."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ForestAdmin/rails-forestadmin"
  spec.metadata["changelog_uri"] = "https://github.com/ForestAdmin/rails-forestadmin/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,lib}/**/*", "LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "dry-configurable", "~> 1.1"
  spec.add_dependency "dry-container", "~> 0.11"
  spec.add_dependency "mono_logger", "~> 1.1"
  spec.add_dependency "rails", ">= 6.1"
  spec.add_dependency "zeitwerk", "~> 2.3"
end
