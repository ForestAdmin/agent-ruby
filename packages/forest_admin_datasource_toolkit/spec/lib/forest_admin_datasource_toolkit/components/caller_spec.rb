require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    describe Caller do
      describe '#initialize' do
        context 'when initialized with standard parameters' do
          let(:caller) do
            described_class.new(
              id: 1,
              email: 'test@example.com',
              first_name: 'John',
              last_name: 'Doe',
              team: 'Operations',
              rendering_id: 123,
              tags: ['tag1'],
              timezone: 'UTC',
              permission_level: 'admin',
              role: 'developer'
            )
          end

          it 'sets all standard attributes' do
            expect(caller.id).to eq(1)
            expect(caller.email).to eq('test@example.com')
            expect(caller.first_name).to eq('John')
            expect(caller.last_name).to eq('Doe')
            expect(caller.team).to eq('Operations')
            expect(caller.rendering_id).to eq(123)
            expect(caller.tags).to eq(['tag1'])
            expect(caller.timezone).to eq('UTC')
            expect(caller.permission_level).to eq('admin')
            expect(caller.role).to eq('developer')
          end
        end

        context 'when initialized with extra keyword arguments' do
          let(:caller) do
            described_class.new(
              id: 1,
              email: 'test@example.com',
              first_name: 'John',
              last_name: 'Doe',
              team: 'Operations',
              rendering_id: 123,
              tags: ['tag1'],
              timezone: 'UTC',
              permission_level: 'admin',
              renderingId: 456,
              firstName: 'Jane',
              lastName: 'Smith',
              permissionLevel: 'user',
              roleId: 789,
              role_id: 987,
              iat: 1234567890
            )
          end

          it 'accepts unknown keyword arguments without raising an error' do
            expect { caller }.not_to raise_error
          end

          it 'sets all standard attributes correctly' do
            expect(caller.id).to eq(1)
            expect(caller.email).to eq('test@example.com')
            expect(caller.first_name).to eq('John')
            expect(caller.last_name).to eq('Doe')
            expect(caller.rendering_id).to eq(123)
          end

          it 'stores extra keyword arguments as instance variables' do
            expect(caller.instance_variable_get(:@renderingId)).to eq(456)
            expect(caller.instance_variable_get(:@firstName)).to eq('Jane')
            expect(caller.instance_variable_get(:@lastName)).to eq('Smith')
            expect(caller.instance_variable_get(:@permissionLevel)).to eq('user')
            expect(caller.instance_variable_get(:@roleId)).to eq(789)
            expect(caller.instance_variable_get(:@role_id)).to eq(987)
            expect(caller.instance_variable_get(:@iat)).to eq(1234567890)
          end
        end

        context 'when initialized with optional parameters omitted' do
          let(:caller) do
            described_class.new(
              id: 1,
              email: 'test@example.com',
              first_name: 'John',
              last_name: 'Doe',
              team: 'Operations',
              rendering_id: 123,
              tags: ['tag1'],
              timezone: 'UTC',
              permission_level: 'admin'
            )
          end

          it 'uses default values for optional parameters' do
            expect(caller.role).to be_nil
            expect(caller.instance_variable_get(:@request)).to eq({})
            expect(caller.instance_variable_get(:@project)).to be_nil
            expect(caller.instance_variable_get(:@environment)).to be_nil
          end
        end
      end

      describe '#to_h' do
        context 'when caller has standard attributes' do
          let(:caller) do
            described_class.new(
              id: 1,
              email: 'test@example.com',
              first_name: 'John',
              last_name: 'Doe',
              team: 'Operations',
              rendering_id: 123,
              tags: ['tag1'],
              timezone: 'UTC',
              permission_level: 'admin',
              role: 'developer',
              request: { ip: '127.0.0.1' },
              project: 'test_project',
              environment: 'development'
            )
          end

          it 'returns a hash with all instance variables' do
            hash = caller.to_h
            expect(hash[:id]).to eq(1)
            expect(hash[:email]).to eq('test@example.com')
            expect(hash[:first_name]).to eq('John')
            expect(hash[:last_name]).to eq('Doe')
            expect(hash[:team]).to eq('Operations')
            expect(hash[:rendering_id]).to eq(123)
            expect(hash[:tags]).to eq(['tag1'])
            expect(hash[:timezone]).to eq('UTC')
            expect(hash[:permission_level]).to eq('admin')
            expect(hash[:role]).to eq('developer')
            expect(hash[:request]).to eq({ ip: '127.0.0.1' })
            expect(hash[:project]).to eq('test_project')
            expect(hash[:environment]).to eq('development')
          end
        end

        context 'when caller has extra keyword arguments' do
          let(:caller) do
            described_class.new(
              id: 1,
              email: 'test@example.com',
              first_name: 'John',
              last_name: 'Doe',
              team: 'Operations',
              rendering_id: 123,
              tags: ['tag1'],
              timezone: 'UTC',
              permission_level: 'admin',
              iat: 1234567890,
              custom_field: 'custom_value'
            )
          end

          it 'includes extra fields in the hash' do
            hash = caller.to_h
            expect(hash[:iat]).to eq(1234567890)
            expect(hash[:custom_field]).to eq('custom_value')
          end
        end
      end
    end
  end
end
