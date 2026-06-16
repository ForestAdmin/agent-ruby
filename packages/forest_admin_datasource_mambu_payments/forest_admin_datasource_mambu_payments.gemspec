lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require_relative 'lib/forest_admin_datasource_mambu_payments/version'

Gem::Specification.new do |spec|
  spec.name        = 'forest_admin_datasource_mambu_payments'
  spec.version     = ForestAdminDatasourceMambuPayments::VERSION
  spec.authors     = ['Forest Admin']
  spec.email       = ['contact@forestadmin.com']
  spec.homepage    = 'https://www.forestadmin.com'
  spec.summary     = 'Mambu Payments (Numeral) datasource for Forest Admin Ruby agent.'
  spec.description = 'Surface Mambu Payments connected accounts, payment orders, ' \
                     'transactions and balances as Forest Admin collections.'
  spec.license     = 'GPL-3.0'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri']    = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/ForestAdmin/agent-ruby'
  spec.metadata['changelog_uri']   = 'https://github.com/ForestAdmin/agent-ruby/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'false'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 6.1'
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'faraday-retry', '~> 2.0'
  spec.add_dependency 'zeitwerk', '~> 2.3'
end
