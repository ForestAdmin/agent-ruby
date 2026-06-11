module ForestAdminDatasourceMambuPayments
  module DisableSearchSupport
    # Records whether search was disabled.
    class FakeSearchCollection
      attr_reader :search_disabled

      def initialize
        @search_disabled = false
      end

      def disable_search
        @search_disabled = true
      end
    end

    class FakeSearchDatasourceCustomizer
      attr_reader :collections

      def initialize
        @collections = Hash.new { |hash, key| hash[key] = FakeSearchCollection.new }
      end

      def customize_collection(name)
        yield(@collections[name])
      end
    end
  end

  RSpec.describe Plugins::DisableSearch do
    subject(:plugin) { described_class.new }

    let(:customizer) { DisableSearchSupport::FakeSearchDatasourceCustomizer.new }

    it 'disables search on every Mambu collection' do
      plugin.run(customizer)

      expect(customizer.collections.keys).to match_array(described_class::COLLECTIONS)
      expect(customizer.collections.values).to all(have_attributes(search_disabled: true))
    end

    it 'raises when installed on a single collection instead of the datasource' do
      expect { plugin.run(nil) }
        .to raise_error(ArgumentError, /must be installed at the datasource level/)
    end
  end
end
