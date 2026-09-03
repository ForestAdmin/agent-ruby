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

    # Intercom truncates a date search to the UTC day -- measured, and against
    # its own documentation, which promises the workspace timezone. `>` answers
    # from the start of the day after the value, `<` before the start of the
    # day of the value. Sent as they come, the two bounds of an interval cancel
    # each other out and `today` answers nothing.
    describe 'a date, and the UTC day Intercom truncates it to' do
      def bound(value, spelling)
        Time.at(call('date', value, spelling: spelling,
                                    operator: spelling == '>' ? operators::GREATER_THAN : operators::LESS_THAN))
            .utc.iso8601
      end

      it 'moves a lower bound back a day, so Intercom answers from the day it names' do
        expect(bound('2026-09-01T08:30:00Z', '>')).to eq('2026-08-31T00:00:00Z')
      end

      it 'moves an upper bound forward a day, so Intercom answers through the day it names' do
        expect(bound('2026-09-01T08:30:00Z', '<')).to eq('2026-09-02T00:00:00Z')
      end

      # An upper bound already sitting on a day boundary names the day to leave
      # out, which is what Intercom answers on its own.
      it 'leaves an upper bound already on a UTC day boundary where it is' do
        expect(bound('2026-09-01T00:00:00Z', '<')).to eq('2026-09-01T00:00:00Z')
      end

      # The pair the toolkit rewrites `today` into, from a caller in UTC: what
      # comes back is that day and nothing else.
      it 'answers the day itself for the two bounds of an interval' do
        expect(bound('2026-09-01T00:00:00Z', '>')).to eq('2026-08-31T00:00:00Z')
        expect(bound('2026-09-01T23:59:59Z', '<')).to eq('2026-09-02T00:00:00Z')
      end

      it 'keeps the offset an ISO8601 timestamp carries' do
        expect(bound('2026-09-01T10:30:00+02:00', '<')).to eq('2026-09-02T00:00:00Z')
      end

      # `FilterFactory` writes the bounds of a previous period with strftime
      # and no offset at all, so a chart comparing to the previous month sends
      # `2026-08-01 00:00:00` meaning the caller's midnight. Read in the
      # process timezone it is a different instant, and a midnight moved by any
      # offset lands on another UTC day once truncated -- a whole day of rows
      # beside the ones the chart named.
      it 'reads a timestamp carrying no offset in the timezone of the caller' do
        # Paris midnight on 1 September is 2026-08-31T22:00:00Z, whose UTC day
        # is the 31st, so `>` must answer from the 31st and sit on the 30th.
        expect(bound('2026-09-01 00:00:00', '>')).to eq('2026-08-30T00:00:00Z')
      end

      it 'reads a whole previous-period window in the timezone of the caller' do
        expect(bound('2026-08-01 00:00:00', '>')).to eq('2026-07-30T00:00:00Z')
        expect(bound('2026-09-01 00:00:00', '<')).to eq('2026-09-01T00:00:00Z')
      end

      # A day with no time of day is the caller's day: it is the timezone the
      # filter was written in that says when that day starts.
      it 'reads a bare date as midnight in the timezone of the caller' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

        expect(bound('2026-09-01', '>')).to eq('2026-08-30T00:00:00Z')
      end

      it 'reads a Ruby Date, a Time, a DateTime and epoch seconds the same way' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

        expect(bound(Date.new(2026, 9, 1), '>')).to eq('2026-08-30T00:00:00Z')
        expect(bound(Time.utc(2026, 9, 1, 8, 30), '<')).to eq('2026-09-02T00:00:00Z')
        expect(bound(DateTime.new(2026, 9, 1, 8, 30, 0), '<')).to eq('2026-09-02T00:00:00Z')
        expect(bound(1_788_251_400, '<')).to eq('2026-09-02T00:00:00Z')
      end

      # A window written in another timezone is answered on the UTC days it
      # overlaps, and an operator has no way of guessing that from the rows.
      it 'reports the UTC day boundary once, when it is not the day of the caller' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

        bound('2026-08-31T22:00:00Z', '>')
        bound('2026-08-31T23:00:00Z', '>')

        expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).once.with(/truncates a date search/)
      end

      it 'stays quiet when the window and the UTC day are the same day anyway' do
        allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

        bound('2026-09-01T08:30:00Z', '>')

        expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
      end

      context 'when the caller names a timezone nothing knows' do
        let(:timezone) { 'Middle-Earth/Shire' }

        # Falling back to UTC silently would move a day boundary by the offset,
        # which is the failure a timezone is read for in the first place.
        it 'reads the day boundary in UTC and says so' do
          allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

          expect(bound('2026-09-01', '>')).to eq('2026-08-31T00:00:00Z')
          expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/unknown timezone/)
        end

        it 'reads a timestamp carrying no offset in UTC and says so' do
          allow(ForestAdminDatasourceIntercom.logger).to receive(:warn)

          expect(bound('2026-09-01 00:00:00', '>')).to eq('2026-08-31T00:00:00Z')
          expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/unknown timezone/)
        end
      end

      context 'when the caller names no timezone at all' do
        let(:timezone) { '  ' }

        it 'reads the day boundary in UTC' do
          expect(bound('2026-09-01', '>')).to eq('2026-08-31T00:00:00Z')
        end
      end

      it 'refuses a string that is not a date' do
        expect { call('date', 'last tuesday', spelling: '>') }
          .to raise_error(UnsupportedOperatorError, /Intercom expects a date on this field/)
      end

      it 'refuses a value that is not a date at all' do
        expect { call('date', { 'day' => 1 }, spelling: '>') }
          .to raise_error(UnsupportedOperatorError, /Intercom expects a date on this field/)
      end

      # Reading either as epoch seconds raises a FloatDomainError, which would
      # leave the read with an error naming a float where the operator asked
      # for a date. The number branch already refuses them; a date is no
      # different.
      it 'refuses a cast that overflowed to Infinity, and a NaN' do
        expect { call('date', Float::INFINITY, spelling: '>') }
          .to raise_error(UnsupportedOperatorError, /Intercom expects a date on this field/)
        expect { call('date', Float::NAN, spelling: '>') }
          .to raise_error(UnsupportedOperatorError, /Intercom expects a date on this field/)
      end

      it 'reads a finite number as the epoch seconds Intercom stores' do
        expect(bound(1_767_225_600, '>')).to eq('2025-12-31T00:00:00Z')
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
        expect(call('number', ['4', 5.0], spelling: 'IN', operator: operators::IN)).to eq([4, 5])
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
