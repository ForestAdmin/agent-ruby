module ForestAdminDatasourceZendesk
  # Tiny PORO standing in for an ActionContextSingle in unit tests. We can't
  # use Struct here because `Struct` mixes in Enumerable, which already defines
  # `#filter` — having a `:filter` member triggers Lint/StructNewOverride and
  # is genuinely ambiguous.
  class FakeActionContext
    attr_reader :form_values, :collection, :filter, :record_id

    def initialize(form_values: nil, collection: nil, filter: nil, record_id: nil)
      @form_values = form_values
      @collection = collection
      @filter = filter
      @record_id = record_id
    end
  end

  RSpec.describe Actions::CreateTicketWithNotification do
    let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
    let(:default_subject) { nil }
    let(:default_message) { nil }
    let(:requester_email_default) { nil }
    let(:datasource_requester_default) { nil }
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource,
                      client: client, custom_field_mapping: {},
                      default_ticket_subject: default_subject,
                      default_ticket_message: default_message,
                      requester_email_default: datasource_requester_default)
    end

    let(:context) { Struct.new(:form_values).new(form_values) }
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
    let(:executor) { described_class.executor(datasource) }

    describe '.build' do
      it 'returns a SINGLE-scoped action with the documented form fields' do
        action = described_class.build(datasource)

        expect(action.scope).to eq(ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::SINGLE)
        labels = action.form.map { |f| f[:label] }
        expect(labels).to eq(['Requester email', 'Subject', 'Message', 'Priority', 'Type', 'Send as internal note'])
      end

      it 'uses RichText for the Message widget' do
        message_field = described_class.build(datasource).form.find { |f| f[:label] == 'Message' }
        expect(message_field[:widget]).to eq('RichText')
      end

      it 'marks Requester email as required' do
        field = described_class.build(datasource).form.first
        expect(field[:label]).to eq('Requester email')
        expect(field[:is_required]).to be(true)
      end
    end

    describe 'requester_email_default' do
      let(:context_double) do
        instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                        get_record: { 'id' => 42, 'email' => 'alice@x.com', 'name' => 'Alice' })
      end

      it 'leaves the field empty (returns nil) when no default is configured' do
        expect(described_class.build(datasource).form.first[:default_value]).to be_nil
      end

      context 'when given a literal email String' do
        it 'uses it verbatim as a static default (no record lookup)' do
          action = described_class.build(datasource, requester_email_default: 'support@example.com')
          expect(action.form.first[:default_value]).to eq('support@example.com')
        end
      end

      context 'when given a Proc resolver' do
        let(:resolver) { ->(record) { record['email'] } }

        it 'pre-fills the email field from the selected record via the resolver' do
          action = described_class.build(datasource, requester_email_default: resolver)
          requester_proc = action.form.first[:default_value]

          expect(requester_proc.call(context_double)).to eq('alice@x.com')
        end

        it 'survives a record lookup that raises (returns nil)' do
          allow(context_double).to receive(:get_record).and_raise(StandardError, 'boom')
          action = described_class.build(datasource, requester_email_default: resolver)

          expect(action.form.first[:default_value].call(context_double)).to be_nil
        end
      end
    end

    describe 'subject / message defaults' do
      let(:default_subject) { 'Welcome' }
      let(:default_message) { '<p>Hi</p>' }

      it 'uses configured static defaults verbatim' do
        action = described_class.build(datasource,
                                       default_subject: default_subject,
                                       default_message: default_message)
        expect(action.form.find { |f| f[:label] == 'Subject' }[:default_value]).to eq('Welcome')
        expect(action.form.find { |f| f[:label] == 'Message' }[:default_value]).to eq('<p>Hi</p>')
      end

      context 'with {{record.<field>}} tokens' do
        let(:context_double) do
          instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                          get_record: { 'id' => 42, 'name' => 'Alice', 'email' => 'alice@x.com' })
        end

        it 'substitutes record fields at form-open time' do
          action = described_class.build(datasource,
                                         default_subject: 'Follow-up for {{record.name}}',
                                         default_message: '<p>Hello {{record.name}} ({{record.email}})</p>')

          subject_proc = action.form.find { |f| f[:label] == 'Subject' }[:default_value]
          message_proc = action.form.find { |f| f[:label] == 'Message' }[:default_value]

          expect(subject_proc.call(context_double)).to eq('Follow-up for Alice')
          expect(message_proc.call(context_double)).to eq('<p>Hello Alice (alice@x.com)</p>')
        end

        it 'falls back to empty strings when the record lookup fails' do
          allow(context_double).to receive(:get_record).and_raise(StandardError, 'boom')
          action = described_class.build(datasource, default_subject: 'Hi {{record.name}}')

          expect(action.form.find { |f| f[:label] == 'Subject' }[:default_value].call(context_double)).to eq('Hi ')
        end
      end
    end

    describe 'executor' do
      context 'with a public html comment (default)' do
        let(:form_values) do
          { 'Requester email' => 'alice@x.com', 'Subject' => 'Refund', 'Message' => 'Hi there',
            'Priority' => 'high', 'Type' => 'question', 'Send as internal note' => false }
        end

        it 'creates a ticket targeting the requester by email and embeds the html comment' do
          allow(client).to receive(:create_ticket) do |payload|
            expect(payload).to eq(
              'requester' => { 'email' => 'alice@x.com' },
              'subject' => 'Refund',
              'comment' => { 'html_body' => 'Hi there', 'public' => true },
              'priority' => 'high',
              'type' => 'question'
            )
            { 'id' => 7 }
          end

          result = executor.call(context, result_builder)
          expect(client).to have_received(:create_ticket)
          expect(result[:message]).to include('Ticket #7', 'notified')
        end
      end

      context 'with internal note' do
        let(:form_values) do
          { 'Requester email' => 'b@x.com', 'Subject' => 'Internal', 'Message' => 'For agents only',
            'Send as internal note' => true }
        end

        it 'flips the comment to private and omits the notify wording' do
          allow(client).to receive(:create_ticket).and_return('id' => 9)

          result = executor.call(context, result_builder)
          expect(client).to have_received(:create_ticket).with(hash_including(
                                                                 'comment' => { 'html_body' => 'For agents only',
                                                                                'public' => false }
                                                               ))
          expect(result[:message]).to include('internal note')
        end
      end

      context 'without a requester email' do
        let(:form_values) { { 'Requester email' => nil, 'Subject' => 'S', 'Message' => 'M' } }

        it 'returns an error and does not call the client' do
          allow(client).to receive(:create_ticket)

          result = executor.call(context, result_builder)
          expect(result[:type]).to eq('Error')
          expect(client).not_to have_received(:create_ticket)
        end
      end

      context 'with empty optional fields' do
        let(:form_values) do
          { 'Requester email' => 'c@x.com', 'Subject' => 'S', 'Message' => 'M',
            'Priority' => nil, 'Type' => '', 'Send as internal note' => nil }
        end

        it 'omits empty optional keys from the payload' do
          allow(client).to receive(:create_ticket) do |payload|
            expect(payload.keys).not_to include('priority', 'type')
            expect(payload['comment']['public']).to be(true)
            { 'id' => 1 }
          end

          executor.call(context, result_builder)
          expect(client).to have_received(:create_ticket)
        end
      end

      context 'with ticket_id_field configured (writeback to host record)' do
        let(:form_values) do
          { 'Requester email' => 'd@x.com', 'Subject' => 'S', 'Message' => 'M',
            'Send as internal note' => false }
        end
        let(:host_collection) { instance_double('RelaxedCollection') } # rubocop:disable RSpec/VerifiedDoubleReference
        let(:filter) { instance_double('Filter') } # rubocop:disable RSpec/VerifiedDoubleReference
        let(:context) do
          FakeActionContext.new(form_values: form_values, collection: host_collection, filter: filter)
        end
        let(:executor_with_writeback) { described_class.executor(datasource, 'zendesk_ticket_id') }

        before do
          allow(client).to receive(:create_ticket).and_return('id' => 77)
        end

        it 'updates the host record with the new ticket id under the configured field' do
          allow(host_collection).to receive(:update)

          result = executor_with_writeback.call(context, result_builder)

          expect(host_collection).to have_received(:update).with(filter, { 'zendesk_ticket_id' => 77 })
          expect(result[:type]).to eq('Success')
          expect(result[:message]).to include('Ticket #77')
          expect(result[:message]).not_to include('warning')
        end

        it 'logs and surfaces a warning when the host update fails but still succeeds' do
          allow(host_collection).to receive(:update).and_raise(StandardError, 'field is read-only')
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)

          result = executor_with_writeback.call(context, result_builder)

          expect(result[:type]).to eq('Success')
          expect(result[:message]).to include('Ticket #77', 'warning', 'field is read-only')
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including('zendesk_ticket_id', 'field is read-only'))
        end

        it 'does not attempt any update when ticket_id_field is nil' do
          allow(host_collection).to receive(:update)

          executor.call(context, result_builder) # executor without ticket_id_field

          expect(host_collection).not_to have_received(:update)
        end
      end
    end

    describe '.register_on' do
      let(:host_collection) do
        Class.new do
          attr_reader :registered

          def initialize = @registered = {}
          def add_action(name, action) = @registered[name] = action
        end.new
      end

      it 'attaches the action to an arbitrary collection-like target' do
        described_class.register_on(host_collection, datasource,
                                    default_subject: 'Welcome',
                                    requester_email_default: ->(r) { r['mail'] })

        expect(host_collection.registered).to have_key(described_class::NAME)
        action = host_collection.registered[described_class::NAME]
        expect(action.form.find { |f| f[:label] == 'Subject' }[:default_value]).to eq('Welcome')
      end

      it 'threads ticket_id_field to the executor (writeback enabled at registration)' do
        described_class.register_on(host_collection, datasource, ticket_id_field: 'zd_id')

        relax = instance_double('RelaxedCollection') # rubocop:disable RSpec/VerifiedDoubleReference
        filter = instance_double('Filter')           # rubocop:disable RSpec/VerifiedDoubleReference
        allow(relax).to receive(:update)
        allow(client).to receive(:create_ticket).and_return('id' => 5)

        ctx = FakeActionContext.new(
          form_values: { 'Requester email' => 'a@b.com', 'Subject' => 'S', 'Message' => 'M' },
          collection: relax, filter: filter
        )
        host_collection.registered[described_class::NAME].execute.call(ctx, result_builder)

        expect(relax).to have_received(:update).with(filter, { 'zd_id' => 5 })
      end
    end

    describe 'datasource-level requester_email_default' do
      context 'when set to a literal email String' do
        let(:datasource_requester_default) { 'support@example.com' }

        it 'becomes the static default of the ZendeskUser action (no record lookup)' do
          user_collection = Collections::User.new(datasource)
          requester_field = user_collection.schema[:actions][described_class::NAME].form.first

          expect(requester_field.default_value).to eq('support@example.com')
        end
      end

      context 'when set to a Proc (advanced)' do
        let(:datasource_requester_default) { ->(record) { record['primary_email'] } }
        let(:context_double) do
          instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                          get_record: { 'primary_email' => 'custom@x.com', 'email' => 'fallback@x.com' })
        end

        it 'overrides the ZendeskUser hardcoded record-reading fallback' do
          user_collection = Collections::User.new(datasource)
          requester_field = user_collection.schema[:actions][described_class::NAME].form.first

          expect(requester_field.default_value.call(context_double)).to eq('custom@x.com')
        end
      end
    end

    describe 'integration with User collection' do
      let(:user_collection) { Collections::User.new(datasource) }
      let(:filter) do
        ForestAdminDatasourceToolkit::Components::Query::Filter.new(
          condition_tree: ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new(
            'id', 'equal', 42
          )
        )
      end

      it 'is registered on the ZendeskUser schema under the documented name' do
        expect(user_collection.schema[:actions]).to have_key(described_class::NAME)
      end

      it 'marks the action form as dynamic so the agent re-fetches it when opened' do
        # The requester_email_default resolver injects a lambda, so the form
        # must be re-evaluated per selected record (not cached statically).
        expect(user_collection.schema[:actions][described_class::NAME].static_form).to be(false)
      end

      it 'returns a typed form through Collection#get_form (regression for NotImplementedError)' do
        allow(client).to receive(:find_user).with(42).and_return(Struct.new(:attributes).new({ 'id' => 42 }))

        form = user_collection.get_form(nil, described_class::NAME, nil, filter)
        labels = form.map(&:label)
        expect(labels).to eq(['Requester email', 'Subject', 'Message', 'Priority', 'Type', 'Send as internal note'])
      end

      it 'runs the action through Collection#execute (regression for NotImplementedError)' do
        allow(client).to receive(:find_user).with(42).and_return(Struct.new(:attributes).new({ 'id' => 42 }))
        allow(client).to receive(:create_ticket).and_return('id' => 99)

        result = user_collection.execute(nil, described_class::NAME,
                                         { 'Requester email' => 'alice@x.com', 'Subject' => 'S', 'Message' => 'M' },
                                         filter)
        expect(client).to have_received(:create_ticket).with(hash_including(
                                                               'requester' => { 'email' => 'alice@x.com' }
                                                             ))
        expect(result[:type]).to eq('Success')
      end
    end
  end
end
