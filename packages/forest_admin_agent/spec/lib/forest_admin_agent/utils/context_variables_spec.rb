require 'spec_helper'
require 'logger'

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
          tags: { 'foo' => 'bar' },
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

      it 'returns nil instead of raising when request_context_variables is nil and the key is not a currentUser one' do
        context_variables = described_class.new(team, user, nil)
        expect(context_variables.get_value('foo.id')).to be_nil
      end

      it 'returns nil instead of raising when request_context_variables is not a Hash' do
        context_variables = described_class.new(team, user, '{"foo.id":100}')
        expect(context_variables.get_value('foo.id')).to be_nil
      end

      it 'does not raise when team is nil and only currentUser fields are requested' do
        context_variables = described_class.new(nil, user, request_context_variables)
        expect(context_variables.get_value('currentUser.firstName')).to eq('John')
      end

      it 'does not raise when user is nil and only currentUser.team fields are requested' do
        context_variables = described_class.new(team, nil, request_context_variables)
        expect(context_variables.get_value('currentUser.team.id')).to eq(1)
      end

      it 'returns nil instead of raising when user is nil and a currentUser user field is requested' do
        context_variables = described_class.new(team, nil, request_context_variables)
        expect(context_variables.get_value('currentUser.firstName')).to be_nil
      end

      context 'when no request context variables are available (e.g. a permission scope)' do
        let(:logger) { instance_double(Logger, log: nil) }

        before { allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger) }

        it 'logs a warning instead of silently degrading with no signal' do
          described_class.new(team, user, nil).get_value('foo.id')

          expect(logger).to have_received(:log).with(
            'Warn', a_string_including("Context variable 'foo.id' could not be resolved")
          )
        end

        it 'does not log when request_context_variables is present but the specific key is missing' do
          described_class.new(team, user, request_context_variables).get_value('some.other.missing.key')

          expect(logger).not_to have_received(:log)
        end
      end
    end
  end
end
