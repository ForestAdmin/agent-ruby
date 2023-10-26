require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Contracts
      include ForestAdminDatasourceToolkit::Components::Query
      describe CollectionContract do
        subject(:collection) { described_class.new }

        let(:caller) do
          Caller.new(
            id: 1,
            email: 'foo@foo.com',
            first_name: 'foo',
            last_name: 'foo',
            team: 1,
            rendering_id: 1,
            tags: {},
            timezone: 'Europe/Paris',
            role: 1,
            permission_level: 'admin'
          )
        end

        it { expect { collection.datasource }.to raise_error(NotImplementedError) }
        it { expect { collection.schema }.to raise_error(NotImplementedError) }
        it { expect { collection.name }.to raise_error(NotImplementedError) }
        it { expect { collection.execute }.to raise_error(NotImplementedError) }
        it { expect { collection.form }.to raise_error(NotImplementedError) }
        it { expect { collection.create(caller, {}) }.to raise_error(NotImplementedError) }
        it { expect { collection.list(caller, Filter.new, Projection.new) }.to raise_error(NotImplementedError) }
        it { expect { collection.update(caller, Filter.new, {}) }.to raise_error(NotImplementedError) }
        it { expect { collection.delete(caller, Filter.new) }.to raise_error(NotImplementedError) }
        it { expect { collection.render_chart }.to raise_error(NotImplementedError) }

        it {
          expect do
            collection.aggregate(caller, Filter.new, Aggregation.new(operation: 'Count'))
          end.to raise_error(NotImplementedError)
        }
      end
    end
  end
end
