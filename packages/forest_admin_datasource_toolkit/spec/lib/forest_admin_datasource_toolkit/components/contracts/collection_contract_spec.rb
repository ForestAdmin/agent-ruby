require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Contracts
      describe CollectionContract do
        subject(:collection) { described_class.new }

        it { expect { collection.datasource }.to raise_error(NotImplementedError) }
        it { expect { collection.schema }.to raise_error(NotImplementedError) }
        it { expect { collection.name }.to raise_error(NotImplementedError) }
        it { expect { collection.execute }.to raise_error(NotImplementedError) }
        it { expect { collection.form }.to raise_error(NotImplementedError) }
        it { expect { collection.create }.to raise_error(NotImplementedError) }
        it { expect { collection.list }.to raise_error(NotImplementedError) }
        it { expect { collection.update }.to raise_error(NotImplementedError) }
        it { expect { collection.delete }.to raise_error(NotImplementedError) }
        it { expect { collection.aggregate }.to raise_error(NotImplementedError) }
        it { expect { collection.render_chart }.to raise_error(NotImplementedError) }
      end
    end
  end
end
