module ForestAdminDatasourcePylon
  # Stand-in for an ActionContextSingle. Not a Struct: `Struct` mixes in
  # Enumerable, which already defines `#filter`, so a `:filter` member is both
  # a cop violation and genuinely ambiguous.
  class FakeCreateContext
    attr_reader :form_values, :collection, :filter

    def initialize(form_values: {}, collection: nil, filter: nil, record: {})
      @form_values = form_values
      @collection = collection
      @filter = filter
      @record = record
    end

    def get_record(_fields = []) = @record
  end

  RSpec.describe Plugins::CreateIssueWithNotification do
    let(:client) { instance_double(ForestAdminDatasourcePylon::Client) }
    let(:datasource) { instance_double(ForestAdminDatasourcePylon::Datasource, client: client) }
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
    let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }
    let(:forest_exception) { ForestAdminDatasourceToolkit::Exceptions::ForestException }
    let(:collection_customizer) do
      Class.new do
        attr_reader :registered

        def initialize = @registered = {}
        def add_action(name, action) = @registered[name] = action
      end.new
    end

    # `sender_email` rides along by default: Pylon refuses an email delivery
    # that does not name the sending address, so the plugin refuses to register
    # one, and an email destination is what the options default to.
    def register(opts = {})
      options = { datasource: datasource, sender_email: 'support@acme.test' }.merge(opts)
      described_class.new.run(nil, collection_customizer, options)
      collection_customizer.registered[opts[:action_name] || described_class::NAME]
    end

    def form_values(overrides = {})
      { 'Requester email' => 'ada@acme.test', 'Subject' => 'Boom',
        'Message' => '<p>it broke</p>' }.merge(overrides)
    end

    def run_action(action, values, context_options = {})
      action.execute.call(FakeCreateContext.new(form_values: values, **context_options), result_builder)
    end

    describe '#run' do
      it 'registers a SINGLE-scoped action under the default name' do
        action = register

        expect(collection_customizer.registered.keys).to contain_exactly(described_class::NAME)
        expect(action.scope).to eq(action_scope::SINGLE)
      end

      # No Type field, unlike the Zendesk form: POST /issues does not take one.
      it 'builds the form Pylon accepts on a create' do
        expect(register.form.map { |field| field[:label] })
          .to eq(['Requester email', 'Subject', 'Message', 'Priority'])
      end

      it 'drops the Priority field when the priority is imposed' do
        expect(register(priority_override: 'urgent').form.map { |field| field[:label] })
          .to eq(['Requester email', 'Subject', 'Message'])
      end

      it 'adds the internal-note checkbox when asked for' do
        expect(register(show_internal_note: true).form.map { |field| field[:label] })
          .to eq(['Requester email', 'Subject', 'Message', 'Priority', 'Send as internal note'])
      end

      # The title is the enum value and the key the content is looked up by, so
      # it has to name one template.
      it 'refuses two templates sharing a title, which would hide the first' do
        expect { register(email_templates: [{ title: 'Outage', content: 'a' }, { title: 'Outage', content: 'b' }]) }
          .to raise_error(forest_exception, /Duplicate email template titles: Outage/)
      end

      it 'refuses a template titled like the option that picks none of them' do
        expect { register(email_templates: [{ title: 'No template', content: 'a' }]) }
          .to raise_error(forest_exception, /cannot be titled/)
      end

      it 'splits the form in two pages when templates are configured' do
        form = register(email_templates: [{ title: 'Outage', content: 'Sorry' }]).form

        expect(form.map { |element| element[:component] }).to eq(%w[Page Page])
        expect(form.first[:elements].map { |field| field[:label] }).to eq(['Template'])
      end

      it 'sends the message as RichText and requires the requester' do
        form = register.form

        expect(form.find { |field| field[:label] == 'Message' }[:widget]).to eq('RichText')
        expect(form.first[:is_required]).to be(true)
      end

      it 'offers the priorities Pylon documents, with no default' do
        priority = register.form.find { |field| field[:label] == 'Priority' }

        expect(priority[:enum_values]).to eq(IssueEnums::PRIORITY)
        expect(priority[:default_value]).to be_nil
      end

      # The plain hashes above only become form elements once the agent builds
      # them, and a form the factory refuses -- Page elements mixed with plain
      # ones, two fields sharing a label -- fails in the panel, not here.
      it 'builds through the real form factory, flat and paged alike' do
        flat  = register(show_internal_note: true)
        paged = register(action_name: 'paged', email_templates: [{ title: 'Outage', content: 'Sorry' }])

        expect { flat.build_elements.validate_fields_ids }.not_to raise_error
        expect { paged.build_elements.validate_fields_ids }.not_to raise_error
        expect(flat.static_form).to be(true)
        expect(paged.static_form).to be(false)
      end

      it 'honors :action_name' do
        register
        register(action_name: 'Open a ticket')

        expect(collection_customizer.registered.keys).to contain_exactly(described_class::NAME, 'Open a ticket')
      end

      it 'raises a ForestException on an unknown destination' do
        expect { register(destination: 'pigeon') }.to raise_error(forest_exception, /Unknown.*pigeon/)
      end

      it 'refuses an email delivery that names no sending address' do
        expect { described_class.new.run(nil, collection_customizer, datasource: datasource) }
          .to raise_error(forest_exception, /:sender_email when the destination is email/)
      end

      # The address belongs to the email app; the other channels never carry it.
      it 'asks for no sending address on another channel' do
        expect { described_class.new.run(nil, collection_customizer, datasource: datasource, destination: 'slack') }
          .not_to raise_error
      end

      it 'raises a ForestException on an unknown priority' do
        expect { register(priority_override: 'critical') }.to raise_error(forest_exception, /Unknown.*critical/)
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

    describe 'the issue an execution creates' do
      it 'posts the form as an issue delivered to the requester by email' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1', 'number' => 12 })

        result = run_action(register, form_values('Priority' => 'high'))

        expect(client).to have_received(:create_issue).with(
          'title' => 'Boom', 'body_html' => '<p>it broke</p>',
          'requester_email' => 'ada@acme.test', 'requester_name' => 'ada',
          'priority' => 'high',
          'destination_metadata' => { 'destination' => 'email', 'email' => 'support@acme.test' }
        )
        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('Issue #12 created and the requester notified by email.')
      end

      it 'carries the sending address and the copies of an email delivery' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1' })

        run_action(register(email_ccs: ['lead@acme.test'], email_bccs: ['audit@acme.test']), form_values)

        expect(client).to have_received(:create_issue).with(
          hash_including('destination_metadata' => { 'destination' => 'email', 'email' => 'support@acme.test',
                                                     'email_ccs' => ['lead@acme.test'],
                                                     'email_bccs' => ['audit@acme.test'] })
        )
      end

      # Those three belong to the email app they are configured on; another
      # channel would carry them for nothing.
      it 'leaves the email settings out of another channel' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1' })

        run_action(register(destination: 'slack'), form_values)

        expect(client).to have_received(:create_issue)
          .with(hash_including('destination_metadata' => { 'destination' => 'slack' }))
      end

      # "Do not contact the requester" is the absence of the key, which is the
      # form the API reference names for it.
      it 'sends no destination at all when the operator asks for an internal issue' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1', 'number' => 12 })

        result = run_action(register(show_internal_note: true),
                            form_values('Send as internal note' => true))

        expect(client).to have_received(:create_issue).with(hash_excluding('destination_metadata'))
        expect(result[:message]).to include('Issue #12 created (internal, the requester was not contacted).')
      end

      it 'sends no destination when the plugin itself is configured as internal' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1' })

        run_action(register(destination: 'internal'), form_values)

        expect(client).to have_received(:create_issue).with(hash_excluding('destination_metadata'))
      end

      it 'imposes the configured priority over the form' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1' })

        run_action(register(priority_override: 'urgent'), form_values('Priority' => 'low'))

        expect(client).to have_received(:create_issue).with(hash_including('priority' => 'urgent'))
      end

      it 'omits the priority when none was picked' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1' })

        run_action(register, form_values)

        expect(client).to have_received(:create_issue).with(hash_excluding('priority'))
      end

      it 'falls back on the id when Pylon answers without a number' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1' })

        expect(run_action(register, form_values)[:message]).to include('Issue #i1 created')
      end

      it 'refuses to post without a requester' do
        allow(client).to receive(:create_issue)

        result = run_action(register, form_values('Requester email' => ''))

        expect(client).not_to have_received(:create_issue)
        expect(result[:type]).to eq('Error')
        expect(result[:message]).to include('Requester email is required.')
      end

      it 'hands the operator the reason Pylon refused the creation' do
        allow(client).to receive(:create_issue)
          .and_raise(APIError.new('Pylon API call failed: create(issues): HTTP 400 account_id is required',
                                  status: 400))

        result = run_action(register, form_values)

        expect(result[:type]).to eq('Error')
        expect(result[:message]).to include('account_id is required')
      end

      it 'lets a Pylon failure that is not the operator\'s to fix stay an error' do
        allow(client).to receive(:create_issue)
          .and_raise(APIError.new('Pylon API call failed: create(issues): HTTP 503', status: 503))

        expect { run_action(register, form_values) }.to raise_error(APIError, /503/)
      end
    end

    describe 'writing the issue id back on the host record' do
      let(:collection) { instance_double(ForestAdminDatasourceCustomizer::Context::RelaxedWrappers::RelaxedCollection) }
      let(:context_options) { { collection: collection, filter: :a_filter } }

      it 'updates the configured column' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1', 'number' => 12 })
        allow(collection).to receive(:update)

        result = run_action(register(issue_id_field: 'pylon_issue_id'), form_values, context_options)

        expect(collection).to have_received(:update).with(:a_filter, { 'pylon_issue_id' => 'i1' })
        expect(result[:type]).to eq('Success')
      end

      it 'writes nothing when no column is configured' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1' })
        allow(collection).to receive(:update)

        run_action(register, form_values, context_options)

        expect(collection).not_to have_received(:update)
      end

      # Pylon has no transaction: the issue exists, so the action succeeds and
      # the failed writeback is a warning inside the success message.
      it 'degrades the success message when the column cannot be written' do
        allow(client).to receive(:create_issue).and_return({ 'id' => 'i1', 'number' => 12 })
        allow(collection).to receive(:update).and_raise(StandardError, 'column is read-only')
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)

        result = run_action(register(issue_id_field: 'pylon_issue_id'), form_values, context_options)

        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('Issue #12 created', 'could not store the issue id', 'read-only')
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn)
          .with(a_string_including('pylon_issue_id', 'read-only'))
      end
    end

    describe 'the record tokens a default is written with' do
      let(:context) { FakeCreateContext.new(record: { 'email' => 'ada@acme.test', 'name' => 'Ada & Co <boss>' }) }

      it 'keeps a token-free default as the literal it is' do
        expect(register(default_subject: 'Outage').form[1][:default_value]).to eq('Outage')
      end

      it 'interpolates the subject without escaping it' do
        subject_field = register(default_subject: 'Outage for {{ record.name }}').form[1]

        expect(subject_field[:default_value].call(context)).to eq('Outage for Ada & Co <boss>')
      end

      # The message ships as body_html and is delivered as such: a record value
      # carrying markup must not become markup.
      it 'escapes the html of a value interpolated into the message' do
        message_field = register(default_message: '<p>Hi {{ record.name }}</p>').form[2]

        expect(message_field[:default_value].call(context)).to eq('<p>Hi Ada &amp; Co &lt;boss&gt;</p>')
      end

      # A default that cannot be resolved must not take the form down with it:
      # the operator gets the template with its tokens emptied, and types.
      it 'logs and interpolates nothing when the record cannot be read' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        unreadable = instance_double(
          ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle
        )
        allow(unreadable).to receive(:get_record).and_raise(StandardError, 'boom')
        subject_field = register(default_subject: 'Outage for {{ record.name }}').form[1]

        expect(subject_field[:default_value].call(unreadable)).to eq('Outage for ')
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn)
          .with(a_string_including('token interpolation', 'boom'))
      end

      it 'reads an empty string for a token the record has no value for' do
        subject_field = register(default_subject: 'Hi {{ record.unknown }}!').form[1]

        expect(subject_field[:default_value].call(context)).to eq('Hi !')
      end

      it 'resolves a lambda requester default against the record' do
        field = register(requester_email_default: ->(record) { record['email'] }).form.first

        expect(field[:default_value].call(context)).to eq('ada@acme.test')
      end

      it 'answers nothing when the requester resolver raises' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        field = register(requester_email_default: ->(_record) { raise 'boom' }).form.first

        expect(field[:default_value].call(context)).to be_nil
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(a_string_including('boom'))
      end
    end

    describe 'picking a template' do
      let(:templates) { [{ title: 'Outage', content: '<p>Sorry {{ record.name }}</p>' }] }
      let(:message_field) do
        register(email_templates: templates).form.last[:elements].find { |field| field[:label] == 'Message' }
      end

      def with_default(default_message)
        register(action_name: "with default #{default_message}", email_templates: templates,
                 default_message: default_message)
          .form.last[:elements].find { |field| field[:label] == 'Message' }
      end

      def context_with_record
        FakeCreateContext.new(record: { 'name' => 'Ada & Co' })
      end

      def template_context(changed:, chosen:, record: {})
        context = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle)
        allow(context).to receive(:field_changed?).with('Template').and_return(changed)
        allow(context).to receive(:get_form_value).with('Template').and_return(chosen)
        allow(context).to receive(:get_record).and_return(record)
        context
      end

      it 'fills the message with the chosen template, tokens escaped' do
        value = message_field[:value].call(template_context(changed: true, chosen: 'Outage',
                                                            record: { 'name' => 'Ada & Co' }))

        expect(value).to eq('<p>Sorry Ada &amp; Co</p>')
      end

      it 'clears the message when the template is taken back and no default was configured' do
        expect(message_field[:value].call(template_context(changed: true, chosen: 'No template'))).to eq('')
      end

      # The wizard carries the configured default like the flat form does: the
      # first page decides whether a template replaces it, not whether the
      # operator is handed an empty required field.
      it 'still fills the first render from the configured default' do
        field = with_default('<p>Hi</p>')

        expect(field[:default_value]).to eq('<p>Hi</p>')
        expect(field[:value]).to be_a(Proc)
      end

      it 'interpolates the default of the first render, tokens escaped' do
        field = with_default('<p>Hi {{ record.name }}</p>')

        expect(field[:default_value].call(context_with_record)).to eq('<p>Hi Ada &amp; Co</p>')
      end

      it 'restores the configured default when the template is taken back' do
        value = with_default('<p>Hi</p>')[:value]
                .call(template_context(changed: true, chosen: 'No template'))

        expect(value).to eq('<p>Hi</p>')
      end

      it 'restores a default carrying tokens, interpolated' do
        value = with_default('<p>Hi {{ record.name }}</p>')[:value]
                .call(template_context(changed: true, chosen: 'No template', record: { 'name' => 'Ada & Co' }))

        expect(value).to eq('<p>Hi Ada &amp; Co</p>')
      end

      # Nil means "leave what the operator typed", which is what keeps their
      # edits across the re-renders of the other fields.
      it 'leaves the message alone while the template does not change' do
        expect(message_field[:value].call(template_context(changed: false, chosen: 'Outage'))).to be_nil
      end
    end
  end
end
