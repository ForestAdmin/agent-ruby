require 'spec_helper'

module ForestAdminAgent
  module Utils
    describe ContextVariables do
      let(:user) do
        {
          id: 1,
          firstName: 'John',
          lastName: 'Doe',
          fullName: 'John Doe',
          email: 'johndoe@forestadmin.com',
          tags: [{ 'key' => 'foo', 'value' => 'bar' }],
          roleId: 1,
          permissionLevel: 'admin'
        }
      end

      let(:team) do
        {
          id: 1,
          name: 'Operations'
        }
      end

      let(:request_context_variables) do
        {
          'foo.id': 100
        }
      end

      it 'returns the request context variable key when the key is not present into the user data' do
        context_variables = described_class.new(team, user, request_context_variables)
        expect(context_variables.get_value(:'foo.id')).to eq(100)
      end

      it 'returns the corresponding value from the key provided of the user data' do
        context_variables = described_class.new(team, user, request_context_variables)
        expect(context_variables.get_value('currentUser.firstName')).to eq('John')
        expect(context_variables.get_value('currentUser.tags.foo')).to eq('bar')
        expect(context_variables.get_value('currentUser.team.id')).to eq(1)
      end
    end
  end
end
