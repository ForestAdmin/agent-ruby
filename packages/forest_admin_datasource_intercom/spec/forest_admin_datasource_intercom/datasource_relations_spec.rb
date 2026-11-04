module ForestAdminDatasourceIntercom
  # Read through the customizer, as the agent does: a key the agent filters a
  # related list on and the collection does not publish is a crash in the
  # operators equivalence decorator, long before any request leaves. Read from
  # the sort layer, the last one under the hooks, which need the agent loaded.
  RSpec.describe Datasource do
    let(:base) { Configuration::REGION_HOSTS[:us] }
    let(:stack) do
      customizer = ForestAdminDatasourceCustomizer::DatasourceCustomizer.new
      customizer.add_datasource(described_class.new(access_token: 's3cr3t', rate_limiter: nil), {})
      customizer.datasource(nil)
      customizer.stack.sort
    end
    let(:caller) do
      ForestAdminDatasourceToolkit::Components::Caller.new(
        id: 1, email: 'ops@acme.test', first_name: 'Ops', last_name: 'Team', team: 'Ops', rendering_id: 1,
        tags: {}, timezone: 'Europe/Paris', permission_level: 'admin'
      )
    end
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:collection_utils) { ForestAdminDatasourceToolkit::Utils::Collection }

    def json(payload)
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def operators_of(collection_name, field)
      stack.get_collection(collection_name).schema[:fields][field].filter_operators
    end

    it 'publishes, on every to-many relation, the operators the agent filters its keys with' do
      stack.collections.each_value do |collection|
        collection.schema[:fields].each do |name, relation|
          case relation
          when ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema
            expect(operators_of(relation.foreign_collection, relation.origin_key))
              .to include(operators::EQUAL), "#{collection.name}.#{name} filters on an unpublished key"
          when ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema
            expect(operators_of(relation.through_collection, relation.origin_key))
              .to include(operators::EQUAL), "#{collection.name}.#{name} filters on an unpublished key"
            expect(operators_of(relation.through_collection, relation.foreign_key))
              .to include(operators::PRESENT), "#{collection.name}.#{name} filters on an unpublished key"
          end
        end
      end
    end

    describe 'the contacts of an account' do
      let(:company) { stack.get_collection('IntercomCompany') }
      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }

      before do
        stub_request(:get, "#{base}/companies/co1/contacts").with(query: hash_including({}))
                                                            .to_return(json('type' => 'list',
                                                                            'data' => [{ 'type' => 'contact',
                                                                                         'id' => 'c1' }],
                                                                            'total_count' => 1, 'pages' => {}))
      end

      it 'lists them from the account endpoint' do
        records = collection_utils.list_relation(
          company, { 'id' => 'co1' }, 'contacts', caller, filter,
          ForestAdminDatasourceToolkit::Components::Query::Projection.new(%w[id])
        )

        expect(records).to eq([{ 'id' => 'c1' }])
      end

      it 'counts them from the account endpoint' do
        aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')

        expect(collection_utils.aggregate_relation(company, { 'id' => 'co1' }, 'contacts', caller, filter,
                                                   aggregation))
          .to eq([{ 'group' => {}, 'value' => 1 }])
      end
    end
  end
end
