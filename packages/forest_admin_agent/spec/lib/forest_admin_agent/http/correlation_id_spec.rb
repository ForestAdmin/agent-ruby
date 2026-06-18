require 'spec_helper'

module ForestAdminAgent
  module Http
    describe CorrelationId do
      after { described_class.reset! }

      it 'lazily generates and memoizes an id within the thread' do
        id = described_class.current

        expect(id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        expect(described_class.current).to eq(id)
      end

      it 'can be seeded by the host' do
        described_class.current = 'req-1'

        expect(described_class.current).to eq('req-1')
      end

      it 'reset! clears it so a fresh id is generated next' do
        first = described_class.current
        described_class.reset!

        expect(described_class.current).not_to eq(first)
      end
    end
  end
end
