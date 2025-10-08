require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    describe Caller do
      let(:valid_params) do
        {
          id: 1,
          email: 'test@example.com',
          first_name: 'John',
          last_name: 'Doe',
          team: 'Engineering',
          rendering_id: 123,
          tags: ['tag1', 'tag2'],
          timezone: 'Europe/Paris',
          permission_level: 'admin'
        }
      end

      describe '#initialize' do
        it 'creates a caller with standard parameters' do
          caller = described_class.new(**valid_params)

          expect(caller.id).to eq(1)
          expect(caller.email).to eq('test@example.com')
          expect(caller.first_name).to eq('John')
          expect(caller.last_name).to eq('Doe')
          expect(caller.team).to eq('Engineering')
          expect(caller.rendering_id).to eq(123)
          expect(caller.tags).to eq(['tag1', 'tag2'])
          expect(caller.timezone).to eq('Europe/Paris')
          expect(caller.permission_level).to eq('admin')
        end

        it 'accepts extra arguments without raising an error' do
          params_with_extra = valid_params.merge(
            extra_field1: 'value1',
            extra_field2: 'value2',
            custom_data: { key: 'value' }
          )

          expect { described_class.new(**params_with_extra) }.not_to raise_error
        end

        it 'creates a valid caller when extra arguments are provided' do
          params_with_extra = valid_params.merge(
            unknown_field: 'some_value',
            another_field: 123
          )

          caller = described_class.new(**params_with_extra)

          expect(caller.id).to eq(1)
          expect(caller.email).to eq('test@example.com')
        end
      end

      describe '#to_h' do
        it 'returns a hash with all instance variables' do
          caller = described_class.new(**valid_params)
          hash = caller.to_h

          expect(hash[:id]).to eq(1)
          expect(hash[:email]).to eq('test@example.com')
          expect(hash[:first_name]).to eq('John')
          expect(hash[:last_name]).to eq('Doe')
          expect(hash[:team]).to eq('Engineering')
          expect(hash[:rendering_id]).to eq(123)
          expect(hash[:tags]).to eq(['tag1', 'tag2'])
          expect(hash[:timezone]).to eq('Europe/Paris')
        end
      end
    end
  end
end
