lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require_relative 'lib/forest_admin_datasource_snowflake/version'

Gem::Specification.new do |spec|
  spec.name        = 'forest_admin_datasource_snowflake'
  spec.version     = ForestAdminDatasourceSnowflake::VERSION
  spec.authors     = ['Forest Admin']
  spec.email       = ['support@forestadmin.com']
  spec.homepage    = 'https://www.forestadmin.com'
  spec.summary     = 'Snowflake datasource for Forest Admin (read-only).'
  spec.description = 'Exposes Snowflake tables and views as Forest Admin collections via ODBC. ' \
                     'Queries are translated from Forest ConditionTrees to parameterized SQL; ' \
                     'no ActiveRecord involvement on the Snowflake side.'
  spec.license     = 'GPL-3.0'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri']         = spec.homepage
  spec.metadata['source_code_uri']      = 'https://github.com/ForestAdmin/agent-ruby'
  spec.metadata['changelog_uri']        = 'https://github.com/ForestAdmin/agent-ruby/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir       = 'exe'
  spec.executables  = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'connection_pool', '~> 2.4'
  spec.add_dependency 'ruby-odbc',       '~> 0.99999'
  spec.add_dependency 'zeitwerk',        '~> 2.3'
end
