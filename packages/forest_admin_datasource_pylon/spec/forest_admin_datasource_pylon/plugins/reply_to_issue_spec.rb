module ForestAdminDatasourcePylon
  class FakeReplyContext
    attr_reader :form_values, :record_ids

    def initialize(form_values: {}, record_ids: ['i1'], records: [])
      @form_values = form_values
      @record_ids = record_ids
      @records = records
    end

    def get_form_value(key) = @form_values[key]
    alias get_record_ids record_ids
    def get_records(_fields = []) = @records
  end

  RSpec.describe Plugins::ReplyToIssue do
    let(:client) { instance_double(ForestAdminDatasourcePylon::Client) }
    let(:datasource) { instance_double(ForestAdminDatasourcePylon::Datasource, client: client) }
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
    let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }
    let(:forest_exception) { ForestAdminDatasourceToolkit::Exceptions::ForestException }
    let(:form) { described_class::FormBuilder }
    let(:collection_customizer) do
      Class.new do
        attr_reader :registered

        def initialize = @registered = {}
        def add_action(name, action) = @registered[name] = action
      end.new
    end

    def register(opts = {})
      described_class.new.run(nil, collection_customizer, { datasource: datasource }.merge(opts))
      collection_customizer.registered[opts[:action_name] || described_class::NAME]
    end

    def message(id, source:, is_private: false, email_info: nil)
      { 'id' => id, 'source' => source, 'is_private' => is_private, 'email_info' => email_info }
    end

    def email_message(id, from:, to:, cc: [])
      message(id, source: 'email', email_info: { 'from_email' => from, 'to_emails' => to, 'cc_emails' => cc })
    end

    def thread(*messages, issue_id: 'i1')
      allow(client).to receive(:fetch_complete_issue_messages).with(issue_id).and_return(messages)
    end

    def field(action, label) = action.form.find { |f| f[:label] == label }

    def run_action(action, values, **context_options)
      action.execute.call(FakeReplyContext.new(form_values: values, **context_options), result_builder)
    end

    describe '#run' do
      it 'registers a SINGLE-scoped action under the default name' do
        expect(register.scope).to eq(action_scope::SINGLE)
        expect(collection_customizer.registered.keys).to contain_exactly(described_class::NAME)
      end

      it 'honors :action_name' do
        register(action_name: 'Answer the customer')

        expect(collection_customizer.registered.keys).to contain_exactly('Answer the customer')
      end

      it 'offers the reply type when internal notes are allowed, which is the default' do
        expect(register.form.map { |f| f[:label] }).to eq(['Reply type', 'Channel', 'To', 'CC', 'Message'])
      end

      it 'drops the reply type when internal notes are not allowed' do
        expect(register(allow_internal_note: false).form.map { |f| f[:label] }).to eq(%w[Channel To CC Message])
      end

      it 'builds through the real form factory' do
        action = register

        expect { action.build_elements.validate_fields_ids }.not_to raise_error
        expect(action.static_form).to be(false)
      end

      it 'raises a ForestException without :datasource' do
        expect { described_class.new.run(nil, collection_customizer, {}) }
          .to raise_error(forest_exception, /requires :datasource/)
      end

      it 'raises a ForestException without a collection' do
        expect { described_class.new.run(nil, nil, datasource: datasource) }
          .to raise_error(forest_exception, /requires a collection/)
      end
    end

    describe 'the message a public reply answers' do
      def resolve(*messages, support: [])
        described_class::ReplyTarget.resolve(messages, support_emails: support)
      end

      it 'is nothing when no message is customer-visible' do
        expect(resolve(message('n1', source: 'slack', is_private: true))).to be_nil
        expect(resolve).to be_nil
      end

      it 'keeps the channel of the first customer-visible message, skipping internal notes' do
        target = resolve(message('n1', source: 'internal', is_private: true), message('m1', source: 'slack'))

        expect(target.source).to eq('slack')
        expect(target.message_id).to eq('m1')
      end

      it 'answers the latest message on that channel, not on another one' do
        target = resolve(message('m1', source: 'slack'), message('m2', source: 'slack'),
                         message('m3', source: 'chat_widget'))

        expect(target.message_id).to eq('m2')
      end

      it 'pre-fills an email reply from the latest email, its sender included' do
        target = resolve(email_message('m1', from: 'old@acme.com', to: ['support@us.io']),
                         email_message('m2', from: 'ada@acme.com', to: ['support@us.io', 'bob@acme.com'],
                                             cc: ['carol@acme.com']),
                         support: ['support@us.io'])

        expect(target.to).to eq(['ada@acme.com', 'bob@acme.com'])
        expect(target.cc).to eq(['carol@acme.com'])
      end

      it 'leaves out the support addresses whatever their case, and duplicates across To and CC' do
        target = resolve(email_message('m1', from: 'Support@Us.io', to: ['ada@acme.com', 'ADA@acme.com'],
                                             cc: ['ada@acme.com', 'support@us.io']),
                         support: ['support@us.io'])

        expect(target.to).to eq(['ada@acme.com'])
        expect(target.cc).to eq([])
      end

      it 'treats a message carrying an email envelope as email, whatever its source says' do
        target = resolve(message('m1', source: 'gmail', email_info: { 'from_email' => 'ada@acme.com' }))

        expect(target.email?).to be(true)
        expect(target.channel_label).to eq('email')
      end

      it 'names the channel for the operator' do
        expect(resolve(message('m1', source: 'slack')).channel_label).to eq('Slack')
        expect(resolve(message('m1', source: 'chat_widget')).channel_label).to eq('chat widget')
        expect(resolve(message('m1', source: nil)).channel_label).to eq('an unnamed channel')
      end
    end

    describe 'the form' do
      let(:context) { FakeReplyContext.new(form_values: { form::TYPE_LABEL => form::PUBLIC_REPLY }) }

      it 'reads the thread once per render, however many fields depend on it' do
        thread(message('m1', source: 'slack'))
        dynamic = register.form.flat_map { |f| f.values_at(:enum_values, :default_value, :if_condition, :value) }

        dynamic.select { |value| value.respond_to?(:call) }.each { |value| value.call(context) }

        expect(client).to have_received(:fetch_complete_issue_messages).once
      end

      it 'offers a public reply by default when the issue has a customer message' do
        thread(message('m1', source: 'slack'))
        type = field(register, form::TYPE_LABEL)

        expect(type[:enum_values].call(context)).to eq([form::PUBLIC_REPLY, form::INTERNAL_NOTE])
        expect(type[:default_value].call(context)).to eq(form::PUBLIC_REPLY)
      end

      it 'offers only an internal note when the issue has no customer message' do
        thread(message('n1', source: 'internal', is_private: true))
        type = field(register, form::TYPE_LABEL)

        expect(type[:enum_values].call(context)).to eq([form::INTERNAL_NOTE])
        expect(type[:default_value].call(context)).to eq(form::INTERNAL_NOTE)
      end

      it 'shows the channel read-only' do
        thread(message('m1', source: 'slack'))
        channel = field(register, form::CHANNEL_LABEL)

        expect(channel[:is_read_only]).to be(true)
        expect(channel[:value].call(context)).to eq('Reply sent via Slack')
      end

      it 'explains why there is no public reply' do
        thread
        channel = field(register, form::CHANNEL_LABEL)

        expect(channel[:value].call(context)).to match(/no customer-visible message.*internal note instead/)
      end

      it 'shows a failed thread read as the failure it is' do
        allow(client).to receive(:fetch_complete_issue_messages)
          .and_raise(ForestAdminDatasourcePylon::APIError.new('HTTP 500 boom', status: 500))

        expect(field(register, form::CHANNEL_LABEL)[:value].call(context))
          .to eq('Could not read the conversation of Pylon issue i1: HTTP 500 boom')
      end

      it 'hides the channel when an internal note is picked' do
        note = FakeReplyContext.new(form_values: { form::TYPE_LABEL => form::INTERNAL_NOTE })

        expect(field(register, form::CHANNEL_LABEL)[:if_condition].call(note)).to be(false)
      end

      describe 'the recipients' do
        it 'are shown and pre-filled on an email issue' do
          thread(email_message('m1', from: 'ada@acme.com', to: ['support@us.io'], cc: ['bob@acme.com']))
          action = register(support_emails: ['SUPPORT@us.io'])

          expect(field(action, form::TO_LABEL)[:if_condition].call(context)).to be(true)
          expect(field(action, form::TO_LABEL)[:default_value].call(context)).to eq(['ada@acme.com'])
          expect(field(action, form::CC_LABEL)[:default_value].call(context)).to eq(['bob@acme.com'])
          expect(field(action, form::TO_LABEL)[:is_required]).to be(true)
        end

        it 'are hidden on another channel' do
          thread(message('m1', source: 'slack'))

          expect(field(register, form::TO_LABEL)[:if_condition].call(context)).to be(false)
          expect(field(register, form::CC_LABEL)[:if_condition].call(context)).to be(false)
        end

        it 'are hidden when the issue has no customer message' do
          thread

          expect(field(register, form::TO_LABEL)[:if_condition].call(context)).to be(false)
        end
      end
    end

    describe 'an execution' do
      let(:posted) { { 'id' => 'r1', 'issue_id' => 'i1' } }

      def values(overrides = {})
        { form::TYPE_LABEL => form::PUBLIC_REPLY, form::MESSAGE_LABEL => '<p>Hi</p>' }.merge(overrides)
      end

      before do
        allow(client).to receive_messages(reply_to_issue: posted, create_issue_note: posted)
      end

      it 'replies to the latest message of the customer channel' do
        thread(message('m1', source: 'slack'), message('m2', source: 'slack'))

        result = run_action(register, values)

        expect(client).to have_received(:reply_to_issue).with('i1', 'body_html' => '<p>Hi</p>', 'message_id' => 'm2')
        expect(result[:type]).to eq('Success')
        expect(result[:message]).to eq('Reply sent via Slack on Pylon issue i1, signed by the account of the ' \
                                       'Pylon API token.')
      end

      it 'emails the recipients the operator kept' do
        thread(email_message('m1', from: 'ada@acme.com', to: ['support@us.io']))

        result = run_action(register,
                            values(form::TO_LABEL => ['ada@acme.com', ' '], form::CC_LABEL => ['bob@acme.com']))

        expect(client).to have_received(:reply_to_issue).with(
          'i1', 'body_html' => '<p>Hi</p>', 'message_id' => 'm1',
                'email_info' => { 'to_emails' => ['ada@acme.com'], 'cc_emails' => ['bob@acme.com'] }
        )
        expect(result[:message]).to start_with('Reply emailed to ada@acme.com on Pylon issue i1')
      end

      it 'refuses an email reply with no recipient, and sends nothing' do
        thread(email_message('m1', from: 'ada@acme.com', to: []))

        result = run_action(register, values(form::TO_LABEL => []))

        expect(result[:type]).to eq('Error')
        expect(result[:message]).to match(/At least one recipient/)
        expect(client).not_to have_received(:reply_to_issue)
      end

      it 'posts an internal note with no target' do
        thread(message('m1', source: 'slack'))

        result = run_action(register, values(form::TYPE_LABEL => form::INTERNAL_NOTE))

        expect(client).to have_received(:create_issue_note).with('i1', 'body_html' => '<p>Hi</p>')
        expect(result[:message]).to eq('Internal note added to Pylon issue i1.')
      end

      it 'never posts a note from an action that does not offer one' do
        thread(message('m1', source: 'slack'))

        run_action(register(allow_internal_note: false), values(form::TYPE_LABEL => form::INTERNAL_NOTE))

        expect(client).not_to have_received(:create_issue_note)
        expect(client).to have_received(:reply_to_issue)
      end

      it 'refuses a public reply on an issue with no customer message' do
        thread(message('n1', source: 'internal', is_private: true))

        result = run_action(register, values)

        expect(result[:type]).to eq('Error')
        expect(result[:message]).to match(/i1 has no customer-visible message.*internal note instead/)
        expect(client).not_to have_received(:reply_to_issue)
      end

      it 'reports a failed thread read as such, never as an issue without customer message' do
        allow(client).to receive(:fetch_complete_issue_messages)
          .and_raise(ForestAdminDatasourcePylon::APIError.new('HTTP 503 down', status: 503))

        result = run_action(register, values)

        expect(result[:message]).to eq('Could not read the conversation of Pylon issue i1: HTTP 503 down')
        expect(client).not_to have_received(:reply_to_issue)
      end

      it 'refuses an empty message' do
        thread(message('m1', source: 'slack'))

        expect(run_action(register, values(form::MESSAGE_LABEL => ' '))[:message]).to eq('A message is required.')
        expect(client).not_to have_received(:reply_to_issue)
      end

      it 'names the missing issue' do
        expect(run_action(register, values, record_ids: [])[:message]).to eq('No Pylon issue selected.')
        expect(run_action(register(issue_id_field: 'pylon_id'), values, records: [{ 'pylon_id' => nil }])[:message])
          .to eq("No Pylon issue id found in 'pylon_id'.")
      end

      it 'reads the issue id from the configured column' do
        thread(message('m1', source: 'slack'), issue_id: 'i9')

        run_action(register(issue_id_field: 'pylon_id'), values, records: [{ 'pylon_id' => 'i9' }])

        expect(client).to have_received(:reply_to_issue).with('i9', hash_including('message_id' => 'm1'))
      end

      it 'hands the operator the reason Pylon refused the reply' do
        thread(message('m1', source: 'slack'))
        allow(client).to receive(:reply_to_issue)
          .and_raise(ForestAdminDatasourcePylon::APIError.new('HTTP 400 message_id is not visible', status: 400))

        result = run_action(register, values)

        expect(result[:type]).to eq('Error')
        expect(result[:message]).to eq('HTTP 400 message_id is not visible')
      end

      it 'lets a Pylon failure that is not the operator\'s to fix stay an error' do
        thread(message('m1', source: 'slack'))
        allow(client).to receive(:reply_to_issue)
          .and_raise(ForestAdminDatasourcePylon::APIError.new('HTTP 502', status: 502))

        expect { run_action(register, values) }.to raise_error(ForestAdminDatasourcePylon::APIError, /502/)
      end
    end
  end
end
