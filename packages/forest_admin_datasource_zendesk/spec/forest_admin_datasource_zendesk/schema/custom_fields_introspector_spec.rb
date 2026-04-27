RSpec.describe ForestAdminDatasourceZendesk::Schema::CustomFieldsIntrospector do
  let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
  let(:introspector) { described_class.new(client) }

  describe '#ticket_custom_fields' do
    it 'maps Zendesk types to Forest column types' do
      allow(client).to receive(:fetch_ticket_fields).and_return([
        { 'id' => 1, 'type' => 'text',     'active' => true, 'removable' => true },
        { 'id' => 2, 'type' => 'integer',  'active' => true, 'removable' => true },
        { 'id' => 3, 'type' => 'date',     'active' => true, 'removable' => true },
        { 'id' => 4, 'type' => 'checkbox', 'active' => true, 'removable' => true }
      ])

      result = introspector.ticket_custom_fields
      types = result.to_h { |cf| [cf[:column_name], cf[:schema].column_type] }
      expect(types).to eq(
        'custom_1' => 'String',
        'custom_2' => 'Number',
        'custom_3' => 'Dateonly',
        'custom_4' => 'Boolean'
      )
    end

    it 'builds Enum schemas with custom_field_options' do
      allow(client).to receive(:fetch_ticket_fields).and_return([
        { 'id' => 5, 'type' => 'dropdown', 'active' => true, 'removable' => true,
          'custom_field_options' => [
            { 'value' => 'gold' }, { 'value' => 'silver' }
          ] }
      ])

      cf = introspector.ticket_custom_fields.first
      expect(cf[:schema].column_type).to eq('Enum')
      expect(cf[:schema].enum_values).to eq(%w[gold silver])
    end

    it 'maps checkbox fields with Boolean operators (EQUAL/NOT_EQUAL only)' do
      allow(client).to receive(:fetch_ticket_fields).and_return([
        { 'id' => 4, 'type' => 'checkbox', 'active' => true, 'removable' => true }
      ])

      cf = introspector.ticket_custom_fields.first
      expect(cf[:schema].column_type).to eq('Boolean')
      expect(cf[:schema].filter_operators).to eq(%w[equal not_equal])
    end

    it 'falls back to String when an Enum has no options' do
      allow(client).to receive(:fetch_ticket_fields).and_return([
        { 'id' => 6, 'type' => 'dropdown', 'active' => true, 'removable' => true,
          'custom_field_options' => [] }
      ])

      cf = introspector.ticket_custom_fields.first
      expect(cf[:schema].column_type).to eq('String')
    end

    it 'skips inactive fields' do
      allow(client).to receive(:fetch_ticket_fields).and_return([
        { 'id' => 7, 'type' => 'text', 'active' => false, 'removable' => true }
      ])
      expect(introspector.ticket_custom_fields).to be_empty
    end

    it 'skips system (non-removable) fields' do
      allow(client).to receive(:fetch_ticket_fields).and_return([
        { 'id' => 8, 'type' => 'text', 'active' => true, 'removable' => false }
      ])
      expect(introspector.ticket_custom_fields).to be_empty
    end

    it 'skips fields with unrecognised types' do
      allow(client).to receive(:fetch_ticket_fields).and_return([
        { 'id' => 9, 'type' => 'mystery', 'active' => true, 'removable' => true }
      ])
      expect(introspector.ticket_custom_fields).to be_empty
    end
  end

  describe '#user_custom_fields' do
    it 'uses key (not id) for the column name when present' do
      allow(client).to receive(:fetch_user_fields).and_return([
        { 'id' => 100, 'type' => 'text', 'key' => 'tier', 'active' => true }
      ])

      result = introspector.user_custom_fields.first
      expect(result[:column_name]).to eq('tier')
      expect(result[:zendesk_key]).to eq('tier')
    end

    it 'falls back to custom_<id> when key is missing' do
      allow(client).to receive(:fetch_user_fields).and_return([
        { 'id' => 101, 'type' => 'text', 'active' => true }
      ])
      expect(introspector.user_custom_fields.first[:column_name]).to eq('custom_101')
    end
  end

  describe '#organization_custom_fields' do
    it 'mirrors user_custom_fields key strategy' do
      allow(client).to receive(:fetch_organization_fields).and_return([
        { 'id' => 200, 'type' => 'text', 'key' => 'plan', 'active' => true }
      ])
      expect(introspector.organization_custom_fields.first[:column_name]).to eq('plan')
    end
  end
end
