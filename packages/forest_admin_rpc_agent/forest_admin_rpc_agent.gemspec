lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require_relative "lib/forest_admin_rpc_agent/version"

Gem::Specification.new do |spec|
  spec.name = "forest_admin_rpc_agent"
  spec.version = ForestAdminRpcAgent::VERSION
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
  spec.files = Dir[
    "{config,lib}/**/*",
    "bin/*",
    "*.gemspec",
    "README.md",
    "LICENSE"
  ]
  spec.bindir = "bin"
  spec.executables = ["forest_admin_rpc_agent"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64"
  spec.add_dependency "bigdecimal"
  spec.add_dependency "csv"
  spec.add_dependency "dry-configurable", "~> 1.1"
  spec.add_dependency "mutex_m"
  spec.add_dependency "ostruct"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "zeitwerk", "~> 2.3"
end
