module ForestAdminDatasourcePylon
  # Stand-in for an action context. The executor only asks it which records were
  # selected -- through a column of the host collection, or through their
  # primary keys -- so the full ActionContext is not needed here.
  class FakeCloseContext
    def initialize(records: [], record_ids: [])
      @records = records
      @record_ids = record_ids
    end

    def get_records(_fields = []) = @records

    # Named after the ActionContext method it stands in for.
    def get_record_ids = @record_ids # rubocop:disable Naming/AccessorMethodName
  end

  RSpec.describe Plugins::CloseIssue do
    let(:client) { instance_double(ForestAdminDatasourcePylon::Client) }
    let(:datasource) { instance_double(ForestAdminDatasourcePylon::Datasource, client: client) }
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
    let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }
    let(:forest_exception) { ForestAdminDatasourceToolkit::Exceptions::ForestException }
    let(:issue_id_field) { 'pylon_issue_id' }
    let(:collection_customizer) do
      Class.new do
        attr_reader :registered

        def initialize = @registered = {}
        def add_action(name, action) = @registered[name] = action
      end.new
    end

    def register(opts = {})
      described_class.new.run(nil, collection_customizer, { datasource: datasource }.merge(opts))
      collection_customizer.registered
    end

    describe '#run' do
      it 'registers one variant per scope' do
        register

        expect(collection_customizer.registered.keys)
          .to contain_exactly('Close Pylon issue', 'Close selected Pylon issues')
      end

      it 'binds the matching ActionScope to each variant' do
        registered = register

        expect(registered['Close Pylon issue'].scope).to eq(action_scope::SINGLE)
        expect(registered['Close selected Pylon issues'].scope).to eq(action_scope::BULK)
      end

      it 'honors :scopes to keep only the requested variant' do
        register(scopes: %i[single])

        expect(collection_customizer.registered.keys).to contain_exactly('Close Pylon issue')
      end

      it 'accepts string scopes as well as symbols' do
        register(scopes: %w[bulk])

        expect(collection_customizer.registered.keys).to contain_exactly('Close selected Pylon issues')
      end

      it 'honors the custom names of both variants' do
        register(action_name: 'Resolve', bulk_action_name: 'Resolve all')

        expect(collection_customizer.registered.keys).to contain_exactly('Resolve', 'Resolve all')
      end

      it 'raises a ForestException on an unknown scope' do
        expect { register(scopes: %i[single weird]) }.to raise_error(forest_exception, /Unknown.*weird/)
      end

      # Through `to_s`, so a value carrying no `to_sym` reaches the error that
      # names it rather than a NoMethodError naming nothing.
      it 'names a scope that is neither a symbol nor a string' do
        expect { register(scopes: [1]) }.to raise_error(forest_exception, /Unknown.*1/)
      end

      it 'raises a ForestException on an empty state' do
        expect { register(state: '  ') }.to raise_error(forest_exception, /state cannot be empty/)
      end

      it 'raises a ForestException without :datasource' do
        expect { described_class.new.run(nil, collection_customizer, {}) }
          .to raise_error(forest_exception, /datasource/)
      end

      it 'raises a ForestException without a collection' do
        expect { described_class.new.run(nil, nil, datasource: datasource) }
          .to raise_error(forest_exception, /collection/)
      end
    end

    describe 'the issues an execution acts on' do
      let(:single) { register(scopes: %i[single], issue_id_field: issue_id_field)['Close Pylon issue'] }
      let(:on_primary_key) { register(scopes: %i[single])['Close Pylon issue'] }

      it 'reads the id from the configured column of the host record' do
        allow(client).to receive(:update_issue)

        result = single.execute.call(FakeCloseContext.new(records: [{ issue_id_field => 'i1' }]), result_builder)

        expect(client).to have_received(:update_issue).with('i1', 'state' => 'closed')
        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('Issue i1 closed.')
      end

      # What an action registered on PylonIssue itself acts on: no column to
      # name, the record's own primary key is the issue.
      it 'reads the primary keys when no column is configured' do
        allow(client).to receive(:update_issue)

        result = on_primary_key.execute.call(FakeCloseContext.new(record_ids: %w[i7]), result_builder)

        expect(client).to have_received(:update_issue).with('i7', 'state' => 'closed')
        expect(result[:message]).to include('Issue i7 closed.')
      end

      # A column of issue ids is not a key, so two host records may name the
      # same issue: writing it twice and counting it twice is one bug apiece.
      it 'writes an issue named by several of the selected records once' do
        allow(client).to receive(:update_issue)
        records = [{ issue_id_field => 'i1' }, { issue_id_field => 'i1' }, { issue_id_field => 'i2' }]

        result = single.execute.call(FakeCloseContext.new(records: records), result_builder)

        expect(client).to have_received(:update_issue).with('i1', 'state' => 'closed').once
        expect(client).to have_received(:update_issue).with('i2', 'state' => 'closed').once
        expect(result[:message]).to include('2 issues')
      end

      it 'returns an error naming the column when no host record carries an id' do
        allow(client).to receive(:update_issue)

        result = single.execute.call(FakeCloseContext.new(records: [{ issue_id_field => nil }]), result_builder)

        expect(client).not_to have_received(:update_issue)
        expect(result[:type]).to eq('Error')
        expect(result[:message]).to include(issue_id_field)
      end

      it 'returns an error when nothing was selected' do
        allow(client).to receive(:update_issue)

        result = on_primary_key.execute.call(FakeCloseContext.new(record_ids: []), result_builder)

        expect(client).not_to have_received(:update_issue)
        expect(result[:message]).to eq('No Pylon issue selected.')
      end

      it 'logs and answers an error when the records cannot be read at all' do
        context = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle)
        allow(context).to receive(:get_records).and_raise(StandardError, 'boom')
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        allow(client).to receive(:update_issue)

        result = single.execute.call(context, result_builder)

        expect(client).not_to have_received(:update_issue)
        expect(result[:type]).to eq('Error')
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn)
          .with(a_string_including(issue_id_field, 'boom'))
      end

      # A ValidationError is the collection refusing the selection in words
      # written for the operator -- PylonIssue naming more issues by id than one
      # page of lookups covers, for one. Degraded to an empty list, it would be
      # reported as "no issue selected" about a selection they can see they made.
      it 'lets a refusal of the selection through rather than reporting nothing selected' do
        context = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContext)
        allow(context).to receive(:get_record_ids).and_raise(UnsupportedOperatorError, 'names 25 issues by id')
        allow(client).to receive(:update_issue)

        expect { on_primary_key.execute.call(context, result_builder) }
          .to raise_error(UnsupportedOperatorError, /names 25 issues by id/)
        expect(client).not_to have_received(:update_issue)
      end
    end

    describe 'the state an execution writes' do
      let(:bulk) { register(scopes: %i[bulk])['Close selected Pylon issues'] }

      it 'patches every selected issue' do
        allow(client).to receive(:update_issue)

        result = bulk.execute.call(FakeCloseContext.new(record_ids: %w[i1 i2 i3]), result_builder)

        %w[i1 i2 i3].each { |id| expect(client).to have_received(:update_issue).with(id, 'state' => 'closed') }
        expect(result[:message]).to include('3 issues closed.')
      end

      # An organization defining its own statuses names the slug it wants; Pylon
      # takes it exactly like a standard one.
      it 'writes the configured state, custom slug included, and says so' do
        allow(client).to receive(:update_issue)
        action = register(scopes: %i[single], state: 'on_hold')['Close Pylon issue']

        result = action.execute.call(FakeCloseContext.new(record_ids: %w[i1]), result_builder)

        expect(client).to have_received(:update_issue).with('i1', 'state' => 'on_hold')
        expect(result[:message]).to include('Issue i1 moved to on_hold.')
      end
    end

    describe 'an execution Pylon refuses' do
      let(:bulk) { register(scopes: %i[bulk])['Close selected Pylon issues'] }
      let(:context) { FakeCloseContext.new(record_ids: %w[i1 i2 i3]) }

      # The point of the per-id rescue: one refusal costs one issue, and the
      # operator is told which, rather than reading a success over a batch that
      # was only half applied.
      it 'keeps going and names what failed' do
        allow(client).to receive(:update_issue)
        allow(client).to receive(:update_issue).with('i2', anything).and_raise(APIError, 'HTTP 404 not found')
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)

        result = bulk.execute.call(context, result_builder)

        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('2 issues closed.', '1 failed: i2.')
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(a_string_including('i2', 'not found'))
      end

      it 'answers an error when every issue failed' do
        allow(client).to receive(:update_issue).and_raise(APIError, 'HTTP 403 forbidden')
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn).exactly(3).times

        result = bulk.execute.call(context, result_builder)

        expect(result[:type]).to eq('Error')
        expect(result[:message]).to include('Failed to close all 3 issues', 'forbidden')
      end

      it 'names the single issue that failed' do
        allow(client).to receive(:update_issue).and_raise(APIError, 'HTTP 403 forbidden')
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        action = register(scopes: %i[single])['Close Pylon issue']

        result = action.execute.call(FakeCloseContext.new(record_ids: %w[i1]), result_builder)

        expect(result[:message]).to include('Failed to close issue i1', 'forbidden')
      end
    end
  end
end
