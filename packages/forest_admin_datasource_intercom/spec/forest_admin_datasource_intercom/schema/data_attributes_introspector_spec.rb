module ForestAdminDatasourceIntercom
  module Schema
    RSpec.describe DataAttributesIntrospector do
      subject(:introspector) { described_class.new(Client.new(configuration), model: 'contact') }

      let(:configuration) { Configuration.new(access_token: 's3cr3t', rate_limiter: nil) }
      let(:base) { configuration.url }

      def json(payload, status = 200)
        { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      def attribute(name, overrides = {})
        { 'type' => 'data_attribute', 'model' => 'contact', 'name' => name, 'label' => name,
          'data_type' => 'string', 'custom' => true, 'archived' => false,
          'api_writable' => true }.merge(overrides)
      end

      def stub_attributes(*attributes, model: 'contact')
        stub_request(:get, "#{base}/data_attributes").with(query: { 'model' => model })
                                                     .to_return(json('type' => 'list', 'data' => attributes))
      end

      it 'reads the attributes of the model it was built for' do
        stub_attributes(attribute('paid_subscriber'), model: 'company')

        expect(described_class.new(Client.new(configuration), model: 'company').attributes.map(&:name))
          .to eq(['paid_subscriber'])
      end

      # The standard attributes are columns the collection declares by hand,
      # with the filters the search table measured. Publishing them again under
      # their `custom_attributes` name would show one fact twice, the
      # unfilterable copy winning nothing.
      it 'leaves out the attributes Intercom defines itself' do
        stub_attributes(attribute('paid_subscriber'), attribute('email', 'custom' => false))

        expect(introspector.attributes.map(&:name)).to eq(['paid_subscriber'])
      end

      it 'leaves out an archived attribute, which the workspace stopped offering' do
        stub_attributes(attribute('paid_subscriber'), attribute('old_plan', 'archived' => true))

        expect(introspector.attributes.map(&:name)).to eq(['paid_subscriber'])
      end

      it 'leaves out an attribute with no name to be a column of' do
        stub_attributes(attribute(''), 'not a hash')

        expect(introspector.attributes).to be_empty
      end

      # Read and carried although every column of this lot is published
      # read-only: it is what lot 4b needs to tell an attribute it may write
      # from one Intercom fills in itself, and reading it again then would be a
      # second boot-time round trip.
      it 'carries api_writable for the lot that writes' do
        stub_attributes(attribute('paid_subscriber'), attribute('lifetime_value', 'api_writable' => false))

        expect(introspector.attributes.map { |a| [a.name, a.api_writable] })
          .to eq([['paid_subscriber', true], ['lifetime_value', false]])
      end

      it 'maps each Intercom data type onto what Forest renders' do
        stub_attributes(attribute('a', 'data_type' => 'integer'), attribute('b', 'data_type' => 'float'),
                        attribute('c', 'data_type' => 'boolean'), attribute('d', 'data_type' => 'date'))

        expect(introspector.attributes.map(&:column_type)).to eq(%w[Number Number Boolean Date])
      end

      # Showing the value Intercom sent beats hiding a column because its type
      # is new.
      it 'reads an unknown data type as a string rather than dropping the column' do
        stub_attributes(attribute('paid_subscriber', 'data_type' => 'quantum'))

        expect(introspector.attributes.first.column_type).to eq('String')
      end

      # Forest lists the fields of a request in a comma-separated query
      # parameter and names a field through a relation with a colon: either one
      # in a column name breaks the projection before the page is read.
      it 'takes the commas and colons out of a column name, keeping the name the payload uses' do
        stub_attributes(attribute('Plan, tier: current'))

        expect(introspector.attributes.map { |a| [a.name, a.column_name] })
          .to eq([['Plan, tier: current', 'Plan tier current']])
      end

      it 'unescapes a name Intercom handed back escaped' do
        stub_attributes(attribute('Ce que j&#39;ai vérifié'))

        expect(introspector.attributes.first.column_name).to eq("Ce que j'ai vérifié")
      end

      # Two attributes landing on one column would share an entry, and the
      # second's values would be read under the first's name -- wrong values
      # rather than missing ones.
      it 'leaves out an attribute colliding with one already kept, and says which' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_attributes(attribute('Plan, tier'), attribute('Plan: tier'))

        expect(introspector.attributes.map(&:name)).to eq(['Plan, tier'])
        expect(ForestAdminDatasourceIntercom.logger)
          .to have_received(:warn).with(/"Plan: tier" is left out.*"Plan tier"/)
      end

      it 'keeps an attribute whose name is nothing but separators out of the schema' do
        stub_attributes(attribute(',,'))

        expect(introspector.attributes).to be_empty
      end

      # A token without the permission costs the columns, never the boot.
      it 'answers no attribute when Intercom refuses the read, and says so' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)
        stub_request(:get, "#{base}/data_attributes").with(query: { 'model' => 'contact' })
                                                     .to_return(json(
                                                                  { 'type' => 'error.list',
                                                                    'errors' => [{ 'code' => 'forbidden' }] }, 403
                                                                ))

        expect(introspector.attributes).to eq([])
        expect(ForestAdminDatasourceIntercom.logger)
          .to have_received(:warn).with(/could not read the contact attributes \(HTTP 403\)/)
      end

      it 'reads Intercom once, however many times it is asked' do
        stub_attributes(attribute('paid_subscriber'))

        2.times { introspector.attributes }

        expect(WebMock).to have_requested(:get, /data_attributes/).once
      end
    end
  end
end
