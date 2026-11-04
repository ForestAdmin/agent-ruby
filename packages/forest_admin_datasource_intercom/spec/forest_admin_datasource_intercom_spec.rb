RSpec.describe ForestAdminDatasourceIntercom do
  describe 'VERSION' do
    # The release `sed` in .releaserc.js only matches `VERSION = "x.y.z"`, and a
    # format it misses is a version that stays behind with no CI failure to say so.
    it 'is a double-quoted semantic version' do
      expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe '.logger' do
    around do |example|
      previous = described_class.logger
      example.run
      described_class.logger = previous
    end

    it 'defaults to a logger named after the package' do
      described_class.logger = nil

      expect(described_class.logger.progname).to eq('forest_admin_datasource_intercom')
    end

    it 'takes the logger it is handed' do
      logger = Logger.new(File::NULL)
      described_class.logger = logger

      expect(described_class.logger).to be(logger)
    end
  end

  describe 'errors' do
    it 'reports a filter Intercom cannot express as a validation error' do
      expect(described_class::UnsupportedOperatorError.new('nope'))
        .to be_a(ForestAdminDatasourceToolkit::Exceptions::ValidationError)
    end

    it 'carries the status and parsed body of a failed call' do
      error = described_class::APIError.new('boom', status: 429, body: { 'type' => 'error.list' })

      expect(error).to have_attributes(message: 'boom', status: 429, body: { 'type' => 'error.list' })
    end

    it 'leaves the status and body unset when the call failed before answering' do
      error = described_class::APIError.new('timeout')

      expect(error).to have_attributes(status: nil, body: nil)
    end
  end
end
