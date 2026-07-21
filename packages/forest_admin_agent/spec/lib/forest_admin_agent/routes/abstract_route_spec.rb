require 'spec_helper'
require 'active_support/isolated_execution_state'
require 'active_support/notifications'

module ForestAdminAgent
  module Routes
    describe AbstractRoute do
      let(:route_class) do
        Class.new(described_class) do
          def setup_routes
            add_route('forest_test', 'get', '/test', ->(args) { { echoed: args.dig(:params, 'collection_name') } })
            self
          end
        end
      end

      it 'wraps the closure in a request.forest_admin notification and passes the return value through' do
        events = []
        subscriber = ::ActiveSupport::Notifications.subscribe('request.forest_admin') do |*args|
          events << ::ActiveSupport::Notifications::Event.new(*args)
        end

        route = route_class.new.routes['forest_test']
        result = route[:closure].call({ params: { 'collection_name' => 'user', 'id' => '42' } })

        ::ActiveSupport::Notifications.unsubscribe(subscriber)

        expect(result).to eq({ echoed: 'user' })
        expect(events.size).to eq(1)
        expect(events.first.payload).to eq({ route: 'forest_test', collection: 'user', id: '42', method: 'get' })
        expect(events.first.duration).to be >= 0
      end
    end
  end
end
