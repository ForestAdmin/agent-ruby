module ForestAdminDatasourceIntercom
  # A collection that leaves `searchable` off has its search emulated by the
  # customizer, as an equality on every String column. On a collection whose
  # endpoint matches no text that is a page that looks searched and is not, so
  # the search has to reach the collection and be refused there.
  RSpec.describe Datasource do
    let(:base) { Configuration::REGION_HOSTS[:us] }
    let(:stack) do
      customizer = ForestAdminDatasourceCustomizer::DatasourceCustomizer.new
      customizer.add_datasource(described_class.new(access_token: 's3cr3t', rate_limiter: nil), {})
      customizer.datasource(nil)
      customizer.stack.search
    end

    def searched(text)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(search: text)
    end

    def projection
      ForestAdminDatasourceToolkit::Components::Query::Projection.new(%w[id])
    end

    describe 'a free-text search through the customizer' do
      it 'refuses a search on tickets by name, sending nothing' do
        expect { stack.get_collection('IntercomTicket').list(nil, searched('facture'), projection) }
          .to raise_error(UnsupportedOperatorError, /IntercomTicket cannot answer a free-text search/)
        expect(WebMock).not_to have_requested(:post, "#{base}/tickets/search")
      end

      it 'refuses a search on companies by name, sending nothing' do
        expect { stack.get_collection('IntercomCompany').list(nil, searched('acme'), projection) }
          .to raise_error(UnsupportedOperatorError, /IntercomCompany cannot answer a free-text search/)
        expect(WebMock).not_to have_requested(:post, "#{base}/companies/list")
      end

      it 'refuses to count a searched company list' do
        aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')

        expect { stack.get_collection('IntercomCompany').aggregate(nil, searched('acme'), aggregation) }
          .to raise_error(UnsupportedOperatorError, /cannot answer a free-text search/)
      end
    end
  end
end
