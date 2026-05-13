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

  RSpec.describe Plugins::CreateTicketWithNotification do
    let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource, client: client, custom_field_mapping: {})
    end
    let(:collection_customizer) do
      Class.new do
        attr_reader :registered

        def initialize = @registered = {}
        def add_action(name, action) = @registered[name] = action
      end.new
    end
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }

    def register(opts = {})
      described_class.new.run(nil, collection_customizer, { datasource: datasource }.merge(opts))
      collection_customizer.registered[opts[:action_name] || described_class::NAME]
    end

    describe '#run' do
      it 'registers a SINGLE-scoped action under the default name with the documented form fields' do
        action = register

        expect(collection_customizer.registered.keys).to contain_exactly(described_class::NAME)
        expect(action.scope).to eq(ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::SINGLE)
        labels = action.form.map { |f| f[:label] }
        expect(labels).to eq(['Requester email', 'Subject', 'Message', 'Priority', 'Type', 'Send as internal note'])
      end

      it 'honors :action_name as a custom label' do
        register
        register(action_name: 'Custom label')

        expect(collection_customizer.registered.keys).to contain_exactly(described_class::NAME, 'Custom label')
      end

      it 'raises ArgumentError without :datasource' do
        expect { described_class.new.run(nil, collection_customizer, {}) }
          .to raise_error(ArgumentError, /datasource/)
      end

      it 'raises ArgumentError without a collection_customizer' do
        expect { described_class.new.run(nil, nil, datasource: datasource) }
          .to raise_error(ArgumentError, /collection/)
      end
    end

    describe 'requester email field' do
      let(:context_double) do
        instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                        get_record: { 'id' => 42, 'email' => 'alice@x.com', 'name' => 'Alice' })
      end

      it 'uses RichText for the Message widget and marks Requester email required' do
        action = register
        message_field = action.form.find { |f| f[:label] == 'Message' }
        expect(message_field[:widget]).to eq('RichText')
        expect(action.form.first[:label]).to eq('Requester email')
        expect(action.form.first[:is_required]).to be(true)
      end

      it 'leaves the field empty when no requester_email_default is configured' do
        expect(register.form.first[:default_value]).to be_nil
      end

      context 'with a literal email String' do
        it 'uses it verbatim as a static default (no record lookup)' do
          action = register(requester_email_default: 'support@example.com')
          expect(action.form.first[:default_value]).to eq('support@example.com')
        end
      end

      context 'with a Proc resolver' do
        let(:resolver) { ->(record) { record['email'] } }

        it 'pre-fills the email field from the selected record via the resolver' do
          action = register(requester_email_default: resolver)
          expect(action.form.first[:default_value].call(context_double)).to eq('alice@x.com')
        end

        it 'returns nil (and logs) when the record lookup raises' do
          allow(context_double).to receive(:get_record).and_raise(StandardError, 'boom')
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)

          action = register(requester_email_default: resolver)
          expect(action.form.first[:default_value].call(context_double)).to be_nil
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including('fetch record', 'StandardError', 'boom'))
        end

        it 'returns nil (and logs) when the resolver proc itself raises' do
          allow(context_double).to receive(:get_record).and_return({ 'email' => 'a@b.com' })
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)
          broken_resolver = ->(_record) { raise StandardError, 'typo in lambda' }

          action = register(requester_email_default: broken_resolver)
          expect(action.form.first[:default_value].call(context_double)).to be_nil
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including('requester_email_default', 'typo in lambda'))
        end
      end
    end

    describe 'subject / message defaults' do
      it 'uses configured static defaults verbatim' do
        action = register(default_subject: 'Welcome', default_message: '<p>Hi</p>')
        expect(action.form.find { |f| f[:label] == 'Subject' }[:default_value]).to eq('Welcome')
        expect(action.form.find { |f| f[:label] == 'Message' }[:default_value]).to eq('<p>Hi</p>')
      end

      context 'with {{record.<field>}} tokens' do
        let(:context_double) do
          instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                          get_record: { 'id' => 42, 'name' => 'Alice', 'email' => 'alice@x.com' })
        end

        it 'substitutes record fields at form-open time' do
          action = register(default_subject: 'Follow-up for {{record.name}}',
                            default_message: '<p>Hello {{record.name}} ({{record.email}})</p>')
          subject_proc = action.form.find { |f| f[:label] == 'Subject' }[:default_value]
          message_proc = action.form.find { |f| f[:label] == 'Message' }[:default_value]

          expect(subject_proc.call(context_double)).to eq('Follow-up for Alice')
          expect(message_proc.call(context_double)).to eq('<p>Hello Alice (alice@x.com)</p>')
        end

        it 'falls back to empty strings when the record lookup fails (logged)' do
          allow(context_double).to receive(:get_record).and_raise(StandardError, 'boom')
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)

          action = register(default_subject: 'Hi {{record.name}}')
          expect(action.form.find { |f| f[:label] == 'Subject' }[:default_value].call(context_double)).to eq('Hi ')
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including('fetch record', 'boom'))
        end
      end
    end

    describe 'HTML escaping on the Message template' do
      let(:context_double) do
        instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                        get_record: { 'name' => "O'Brien <admin>", 'note' => '<script>alert(1)</script>' })
      end

      it 'escapes interpolated values in the Message (RichText -> html_body)' do
        action = register(default_message: '<p>Hi {{record.name}} - {{record.note}}</p>')
        message_proc = action.form.find { |f| f[:label] == 'Message' }[:default_value]

        expect(message_proc.call(context_double)).to eq(
          '<p>Hi O&#39;Brien &lt;admin&gt; - &lt;script&gt;alert(1)&lt;/script&gt;</p>'
        )
      end

      it 'leaves Subject interpolation unescaped (plain-text field)' do
        action = register(default_subject: 'Re: {{record.name}}')
        subject_proc = action.form.find { |f| f[:label] == 'Subject' }[:default_value]

        expect(subject_proc.call(context_double)).to eq("Re: O'Brien <admin>")
      end
    end

    describe 'executor' do
      let(:context) { Struct.new(:form_values).new(form_values) }

      context 'with a public html comment (default)' do
        let(:form_values) do
          { 'Requester email' => 'alice@x.com', 'Subject' => 'Refund', 'Message' => 'Hi there',
            'Priority' => 'high', 'Type' => 'question', 'Send as internal note' => false }
        end

        it 'creates a ticket targeting the requester by email and embeds the html comment' do
          allow(client).to receive(:create_ticket) do |payload|
            expect(payload).to eq(
              'requester' => { 'email' => 'alice@x.com', 'name' => 'alice' },
              'subject' => 'Refund',
              'comment' => { 'html_body' => 'Hi there', 'public' => true },
              'priority' => 'high',
              'type' => 'question'
            )
            { 'id' => 7 }
          end

          result = register.execute.call(context, result_builder)
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

          result = register.execute.call(context, result_builder)
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

          result = register.execute.call(context, result_builder)
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

          register.execute.call(context, result_builder)
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

        before { allow(client).to receive(:create_ticket).and_return('id' => 77) }

        it 'updates the host record with the new ticket id under the configured field' do
          allow(host_collection).to receive(:update)
          action = register(ticket_id_field: 'last_zendesk_ticket_id')

          result = action.execute.call(context, result_builder)

          expect(host_collection).to have_received(:update).with(filter, { 'last_zendesk_ticket_id' => 77 })
          expect(result[:type]).to eq('Success')
          expect(result[:message]).to include('Ticket #77')
          expect(result[:message]).not_to include('warning')
        end

        it 'logs and surfaces a warning when the host update fails but still succeeds' do
          allow(host_collection).to receive(:update).and_raise(StandardError, 'field is read-only')
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)
          action = register(ticket_id_field: 'last_zendesk_ticket_id')

          result = action.execute.call(context, result_builder)

          expect(result[:type]).to eq('Success')
          expect(result[:message]).to include('Ticket #77', 'warning', 'field is read-only')
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including('last_zendesk_ticket_id', 'field is read-only'))
        end

        it 'does not attempt any update when ticket_id_field is omitted' do
          allow(host_collection).to receive(:update)

          register.execute.call(context, result_builder)

          expect(host_collection).not_to have_received(:update)
        end
      end
    end

    describe 'email_templates wizard' do
      let(:templates) do
        [{ title: 'Welcome', content: '<p>Welcome aboard!</p>' },
         { title: 'Refund',  content: '<p>Refund processed.</p>' }]
      end

      it 'flips the form into a two-page wizard (Template first, body second)' do
        action = register(email_templates: templates)

        expect(action.form.size).to eq(2)
        page_one, page_two = action.form
        expect(page_one[:component]).to eq('Page')
        expect(page_one[:elements].map { |f| f[:label] }).to eq(['Template'])
        expect(page_two[:elements].map { |f| f[:label] })
          .to eq(['Requester email', 'Subject', 'Message', 'Priority', 'Type', 'Send as internal note'])
      end

      it 'lists No template + each template title in the dropdown' do
        template_field = register(email_templates: templates).form.first[:elements].first
        expect(template_field[:enum_values]).to eq(['No template', 'Welcome', 'Refund'])
        expect(template_field[:default_value]).to eq('No template')
      end

      it 'pre-fills Message via `value:` when Template was the just-changed field' do
        message_field = register(email_templates: templates).form.last[:elements].find { |f| f[:label] == 'Message' }
        ctx = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                              field_changed?: true, get_form_value: 'Refund')

        expect(message_field[:value].call(ctx)).to eq('<p>Refund processed.</p>')
      end

      it "yields an empty Message when 'No template' was just selected" do
        message_field = register(email_templates: templates).form.last[:elements].find { |f| f[:label] == 'Message' }
        ctx = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                              field_changed?: true, get_form_value: 'No template')

        expect(message_field[:value].call(ctx)).to eq('')
      end

      it 'returns nil (carry over current input) when another field triggered the re-fetch' do
        message_field = register(email_templates: templates).form.last[:elements].find { |f| f[:label] == 'Message' }
        ctx = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                              field_changed?: false)

        expect(message_field[:value].call(ctx)).to be_nil
      end

      it 'interpolates {{record.<field>}} tokens inside the selected template content' do
        templated = [{ title: 'Welcome', content: '<p>Hi {{record.name}} ({{record.email}})</p>' }]
        message_field = register(email_templates: templated).form.last[:elements].find { |f| f[:label] == 'Message' }
        ctx = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                              field_changed?: true, get_form_value: 'Welcome',
                              get_record: { 'name' => 'Alice', 'email' => 'a@b.com' })

        expect(message_field[:value].call(ctx)).to eq('<p>Hi Alice (a@b.com)</p>')
      end

      it 'HTML-escapes interpolated record values inside template content' do
        templated = [{ title: 'Bug', content: '<p>{{record.note}}</p>' }]
        message_field = register(email_templates: templated).form.last[:elements].find { |f| f[:label] == 'Message' }
        ctx = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle,
                              field_changed?: true, get_form_value: 'Bug',
                              get_record: { 'note' => '<script>x</script>' })

        expect(message_field[:value].call(ctx)).to eq('<p>&lt;script&gt;x&lt;/script&gt;</p>')
      end

      it 'keeps the flat form when no templates are configured' do
        expect(register(email_templates: []).form.first[:component]).to be_nil # not a Page
      end
    end

    describe 'priority_override / type_override' do
      it 'omits the Priority field and forces the value in the payload' do
        allow(client).to receive(:create_ticket).and_return('id' => 1)

        action = register(priority_override: 'urgent')
        expect(action.form.map { |f| f[:label] }).not_to include('Priority')

        action.execute.call(
          FakeActionContext.new(form_values: { 'Requester email' => 'a@b.com',
                                               'Subject' => 'S', 'Message' => 'M' }),
          result_builder
        )
        expect(client).to have_received(:create_ticket).with(hash_including('priority' => 'urgent'))
      end

      it 'omits the Type field and forces the value in the payload' do
        allow(client).to receive(:create_ticket).and_return('id' => 1)

        action = register(type_override: 'incident')
        expect(action.form.map { |f| f[:label] }).not_to include('Type')

        action.execute.call(
          FakeActionContext.new(form_values: { 'Requester email' => 'a@b.com',
                                               'Subject' => 'S', 'Message' => 'M' }),
          result_builder
        )
        expect(client).to have_received(:create_ticket).with(hash_including('type' => 'incident'))
      end

      it 'forces the override even when the form value is also present' do
        allow(client).to receive(:create_ticket).and_return('id' => 1)
        register(priority_override: 'urgent').execute.call(
          FakeActionContext.new(form_values: { 'Requester email' => 'a@b.com', 'Subject' => 'S',
                                               'Message' => 'M', 'Priority' => 'low' }),
          result_builder
        )
        expect(client).to have_received(:create_ticket).with(hash_including('priority' => 'urgent'))
      end
    end

    describe 'requester name auto-derivation' do
      it 'sends the email local-part as requester.name in the payload' do
        allow(client).to receive(:create_ticket).and_return('id' => 1)
        register.execute.call(
          FakeActionContext.new(form_values: { 'Requester email' => 'john.doe@acme.com',
                                               'Subject' => 'S', 'Message' => 'M' }),
          result_builder
        )
        expect(client).to have_received(:create_ticket).with(hash_including(
                                                               'requester' => { 'email' => 'john.doe@acme.com',
                                                                                'name' => 'john.doe' }
                                                             ))
      end
    end

    describe 'sender_email' do
      it 'maps to Zendesk `recipient` in the payload when configured' do
        allow(client).to receive(:create_ticket).and_return('id' => 1)
        register(sender_email: 'support@acme.com').execute.call(
          FakeActionContext.new(form_values: { 'Requester email' => 'a@b.com',
                                               'Subject' => 'S', 'Message' => 'M' }),
          result_builder
        )
        expect(client).to have_received(:create_ticket).with(hash_including('recipient' => 'support@acme.com'))
      end

      it 'omits recipient from the payload when sender_email is blank' do
        allow(client).to receive(:create_ticket) do |payload|
          expect(payload).not_to have_key('recipient')
          { 'id' => 1 }
        end
        register.execute.call(
          FakeActionContext.new(form_values: { 'Requester email' => 'a@b.com',
                                               'Subject' => 'S', 'Message' => 'M' }),
          result_builder
        )
        expect(client).to have_received(:create_ticket)
      end
    end
  end
end
