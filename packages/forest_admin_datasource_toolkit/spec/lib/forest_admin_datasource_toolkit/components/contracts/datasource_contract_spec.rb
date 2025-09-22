require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Contracts
      describe DatasourceContract do
        subject(:datasource) { described_class.new }

        it { expect { datasource.collections }.to raise_error(NotImplementedError) }
        it { expect { datasource.get_collection('__foo__') }.to raise_error(NotImplementedError) }
        it { expect { datasource.add_collection('__collection__') }.to raise_error(NotImplementedError) }
        it { expect { datasource.render_chart('caller', 'chart') }.to raise_error(NotImplementedError) }
      end
    end
  end
end
