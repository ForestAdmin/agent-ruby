module ForestAdminDatasourceIntercom
  module Schema
    RSpec.describe TicketAttributesIntrospector do
      subject(:introspector) { described_class.new(Client.new(configuration)) }

      let(:configuration) { Configuration.new(access_token: 's3cr3t', rate_limiter: nil) }
      let(:base) { configuration.url }

      def json(payload, status = 200)
        { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      def attribute(name, id, data_type: 'string', archived: false)
        { 'id' => id, 'name' => name, 'data_type' => data_type, 'archived' => archived }
      end

      def ticket_type(id, name, *attributes)
        { 'type' => 'ticket_type', 'id' => id, 'name' => name,
          'ticket_type_attributes' => { 'type' => 'list', 'data' => attributes } }
      end

      def stub_types(*types)
        stub_request(:get, "#{base}/ticket_types").to_return(json('type' => 'list', 'data' => types))
      end

      it 'reads one entry per attribute name' do
        stub_types(ticket_type('1', 'Bug', attribute('Severity', '9001')),
                   ticket_type('2', 'Task', attribute('Due', '9002', data_type: 'datetime')))

        expect(introspector.attributes.map(&:name)).to contain_exactly('Severity', 'Due')
      end

      # Measured: two ticket types share the names `_default_title_` and
      # `_default_description_` while carrying different attribute ids. A union
      # column has no single id to be filtered by, which is why these ship
      # unfilterable -- and why the ids are kept, since that is what a filter
      # per ticket type will need.
      it 'keeps the id each ticket type gives the same attribute name' do
        stub_types(ticket_type('1', 'Bug', attribute('_default_title_', '14162161')),
                   ticket_type('2', 'Task', attribute('_default_title_', '14162165')))

        expect(introspector.attributes.map(&:ids_by_ticket_type))
          .to eq([{ '1' => '14162161', '2' => '14162165' }])
      end

      it 'maps the Intercom data types onto what Forest renders' do
        stub_types(ticket_type('1', 'Bug', attribute('n', '1', data_type: 'integer'),
                               attribute('d', '2', data_type: 'decimal'),
                               attribute('b', '3', data_type: 'boolean'),
                               attribute('t', '4', data_type: 'datetime'),
                               attribute('l', '5', data_type: 'list'),
                               attribute('f', '6', data_type: 'files')))

        expect(introspector.attributes.map(&:column_type)).to eq(%w[Number Number Boolean Date String Json])
      end

      # Showing the value Intercom sent beats hiding a column because its type
      # is one this datasource has not met yet.
      it 'reads an unknown data type as a string rather than dropping the column' do
        stub_types(ticket_type('1', 'Bug', attribute('x', '1', data_type: 'quantum')))

        expect(introspector.attributes.map(&:column_type)).to eq(%w[String])
      end

      it 'leaves out an archived attribute, which is not offered any more' do
        stub_types(ticket_type('1', 'Bug', attribute('Gone', '1', archived: true), attribute('Here', '2')))

        expect(introspector.attributes.map(&:name)).to eq(%w[Here])
      end

      it 'leaves out an attribute with no name to be a column of' do
        stub_types(ticket_type('1', 'Bug', attribute('', '1')))

        expect(introspector.attributes).to be_empty
      end

      it 'reads a ticket type declaring no attribute as declaring none' do
        stub_types({ 'id' => '1', 'name' => 'Bug' })

        expect(introspector.attributes).to be_empty
      end

      # It runs while Rails is starting, so it waits far less than a request
      # that already has a page on screen.
      it 'reads through the boot connection' do
        slow = Configuration.new(access_token: 's3cr3t', rate_limiter: nil, boot_timeout: 2, timeout: 30)
        client = Client.new(slow)
        stub_types

        described_class.new(client).attributes

        expect(client.send(:boot_connection).options.timeout).to eq(2)
      end

      it 'reads once and remembers, a schema being built once' do
        stub_types(ticket_type('1', 'Bug', attribute('Severity', '9001')))

        2.times { introspector.attributes }

        expect(WebMock).to have_requested(:get, "#{base}/ticket_types").once
      end

      # A token without the ticket-types permission costs the attribute columns,
      # never the boot of the agent.
      it 'degrades to no attribute when the read is refused' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/ticket_types").to_return(json({ 'errors' => [{ 'code' => 'forbidden' }] }, 403))

        expect(introspector.attributes).to eq([])
        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/boots without its attribute/)
      end
    end
  end
end
