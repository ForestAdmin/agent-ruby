module ForestAdminDatasourceIntercom
  RSpec.describe Query::FilterValue do
    subject(:formatter) { described_class.new(collection: 'IntercomConversation', timezone: timezone) }

    let(:timezone) { 'Europe/Paris' }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:nodes) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes }

    def field(type, operators = ['='])
      Query::SearchFields::Field.new(column: 'c', field: 'c', type: type, operators: operators, source: 'spec')
    end

    def call(type, value, spelling: '=', operator: nil)
      leaf = nodes::ConditionTreeLeaf.new('c', operator || operators::EQUAL, value)

      formatter.call(leaf, field(type), spelling)
    end

    describe 'a date' do
      # Intercom stores and compares its dates as epoch seconds.
      it 'sends an ISO8601 timestamp as the second it names' do
        expect(call('date', '2026-09-01T08:30:00Z')).to eq(1_788_251_400)
      end

      it 'keeps the offset an ISO8601 timestamp carries' do
        expect(call('date', '2026-09-01T10:30:00+02:00')).to eq(1_788_251_400)
      end

      # A day with no time of day is the caller's day: it is the timezone the
      # filter was written in that says when that day starts, not the server's.
      it 'reads a bare date as midnight in the timezone of the caller' do
        expect(call('date', '2026-09-01')).to eq(Time.utc(2026, 8, 31, 22).to_i)
      end

      it 'reads a Ruby Date the same way' do
        expect(call('date', Date.new(2026, 9, 1))).to eq(Time.utc(2026, 8, 31, 22).to_i)
      end

      it 'takes a Time and a DateTime as the instant they are' do
        expect(call('date', Time.utc(2026, 9, 1, 8, 30))).to eq(1_788_251_400)
        expect(call('date', DateTime.new(2026, 9, 1, 8, 30, 0))).to eq(1_788_251_400)
      end

      it 'leaves epoch seconds alone' do
        expect(call('date', 1_788_251_400)).to eq(1_788_251_400)
      end

      # Falling back to UTC silently would move a day boundary by the offset,
      # which is the failure a timezone is read for in the first place.
      context 'when the caller names a timezone nothing knows' do
        let(:timezone) { 'Middle-Earth/Shire' }

        it 'reads the day boundary in UTC and says so' do
          allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

          expect(call('date', '2026-09-01')).to eq(Time.utc(2026, 9, 1).to_i)
          expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/unknown timezone/)
        end
      end

      context 'when the caller names no timezone at all' do
        let(:timezone) { '  ' }

        it 'reads the day boundary in UTC' do
          expect(call('date', '2026-09-01')).to eq(Time.utc(2026, 9, 1).to_i)
        end
      end

      it 'refuses a string that is not a date' do
        expect { call('date', 'last tuesday') }
          .to raise_error(UnsupportedOperatorError, /Intercom expects a date on this field/)
      end

      it 'refuses a value that is not a date at all' do
        expect { call('date', { 'day' => 1 }) }
          .to raise_error(UnsupportedOperatorError, /Intercom expects a date on this field/)
      end
    end

    describe 'a number' do
      # The agent casts every Number column with `to_f`, so an integer field
      # would otherwise be filtered with `42.0`, a form none of its values carry.
      it 'sends a whole float as the integer it is' do
        expect(call('number', 42.0)).to eq(42)
      end

      it 'keeps a decimal, and an integer, as they are' do
        expect(call('number', 42.5)).to eq(42.5)
        expect(call('number', 42)).to eq(42)
      end

      it 'reads an integer written as a string' do
        expect(call('number', '42')).to eq(42)
      end

      it 'reads a decimal written as a string' do
        expect(call('number', '42.5')).to eq(42.5)
      end

      # `to_i` raises on both, and so does the JSON encoder a step later, as a
      # 500 naming nothing the operator can act on.
      it 'refuses a cast that overflowed and a value that is not a number' do
        expect { call('number', Float::INFINITY) }.to raise_error(UnsupportedOperatorError, /expects a number/)
        expect { call('number', 'many') }.to raise_error(UnsupportedOperatorError, /expects a number/)
        expect { call('number', []) }.to raise_error(UnsupportedOperatorError, /expects a number/)
      end
    end

    describe 'a boolean' do
      it 'sends a flag as a boolean, whichever way the filter spelled it' do
        expect(call('boolean', true)).to be(true)
        expect(call('boolean', false)).to be(false)
        expect(call('boolean', 'true')).to be(true)
        expect(call('boolean', 'false')).to be(false)
      end

      it 'refuses anything else, rather than reading it as truthy' do
        expect { call('boolean', 'yes') }.to raise_error(UnsupportedOperatorError, /expects a true or a false/)
      end
    end

    describe 'a list' do
      it 'formats every value of an IN the way the field takes it' do
        expect(call('date', %w[2026-09-01 2026-09-02], spelling: 'IN', operator: operators::IN))
          .to eq([Time.utc(2026, 8, 31, 22).to_i, Time.utc(2026, 9, 1, 22).to_i])
      end

      # A filter matching everything is not what an empty list was asked for.
      it 'refuses an empty list' do
        expect { call('string', [], spelling: 'IN', operator: operators::IN) }
          .to raise_error(UnsupportedOperatorError, /empty list/)
      end

      # `not_in [nil, 'open']` was asked to exclude the records carrying neither
      # and would come back including the blank ones.
      it 'refuses a list holding a blank, rather than dropping it' do
        expect { call('string', [nil, 'open'], spelling: 'NIN', operator: operators::NOT_IN) }
          .to raise_error(UnsupportedOperatorError, /cannot filter "c" for absence/)
      end
    end

    describe 'a condition on the absence of a value' do
      # `present`, `blank` and `missing` are derived from an equality above this
      # datasource and rewritten into a comparison with an empty value. Intercom
      # would answer it as if the empty string were a value of its own.
      it 'refuses the rewritten comparison and says to filter on a value' do
        expect { call('string', nil) }
          .to raise_error(UnsupportedOperatorError, /matches values and has no operator for the lack of one/)
      end

      it 'refuses an empty string the same way' do
        expect { call('string', '') }.to raise_error(UnsupportedOperatorError, /for absence/)
      end
    end

    describe 'a string' do
      it 'sends it as it came' do
        expect(call('string', 'open')).to eq('open')
      end

      it 'sends a text the same way' do
        expect(call('text', 'facture')).to eq('facture')
      end
    end
  end
end
