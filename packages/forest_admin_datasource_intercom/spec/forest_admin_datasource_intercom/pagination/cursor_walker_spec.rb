module ForestAdminDatasourceIntercom
  module Pagination
    RSpec.describe CursorWalker do
      subject(:walker) { described_class.new }

      let(:asked) { [] }

      def record(id)
        { 'id' => id }
      end

      def page(records, next_cursor: nil)
        Client::Page.new(records: records, next_cursor: next_cursor, total_count: nil)
      end

      # A page source Intercom's own shape: each page advertises the cursor of
      # the next one, and the last advertises nothing.
      def source(*pages)
        queue = pages.dup

        lambda do |per_page, cursor|
          asked << [per_page, cursor]
          queue.shift || page([])
        end
      end

      def ids(records)
        records.map { |r| r['id'] }
      end

      it 'serves a window one page already covers' do
        records = walker.walk(offset: 0, limit: 2, &source(page([record('a'), record('b')], next_cursor: 'c1')))

        expect(ids(records)).to eq(%w[a b])
      end

      it 'asks only for the records the window still needs' do
        walker.walk(offset: 0, limit: 3, &source(page([record('a'), record('b'), record('c')])))

        expect(asked).to eq([[3, nil]])
      end

      it 'walks pages until the window is covered, then slices the offset out' do
        pages = source(page([record('a'), record('b')], next_cursor: 'c1'),
                       page([record('c'), record('d')], next_cursor: 'c2'))

        records = walker.walk(offset: 2, limit: 2, &pages)

        expect(ids(records)).to eq(%w[c d])
        expect(asked).to eq([[4, nil], [2, 'c1']])
      end

      it 'follows the cursor each page advertises' do
        walker.walk(offset: 0, limit: 4, &source(page([record('a')], next_cursor: 'c1'),
                                                 page([record('b')], next_cursor: 'c2'),
                                                 page([record('c')])))

        expect(asked.map(&:last)).to eq([nil, 'c1', 'c2'])
      end

      it 'stops where Intercom stops advertising a next page' do
        records = walker.walk(offset: 0, limit: 10, &source(page([record('a')])))

        expect(ids(records)).to eq(%w[a])
        expect(asked.size).to eq(1)
      end

      it 'stops on an empty page' do
        records = walker.walk(offset: 0, limit: 10, &source(page([], next_cursor: 'c1')))

        expect(records).to be_empty
      end

      # None of this happens against Intercom today, but a walk driven by a
      # remote value stops on its own terms rather than on the caps only.
      it 'stops on a cursor it has already followed' do
        pages = source(page([record('a')], next_cursor: 'loop'),
                       page([record('b')], next_cursor: 'loop'),
                       page([record('c')], next_cursor: 'loop'))

        walker.walk(offset: 0, limit: 10, &pages)

        expect(asked.size).to eq(2)
      end

      # Intercom documents duplicates on a dataset that moves between two
      # paginated requests, and conversations move constantly. Two rows carrying
      # one id is what a list view renders as two identical lines.
      it 'drops a record a previous page already served' do
        pages = source(page([record('a'), record('b')], next_cursor: 'c1'),
                       page([record('b'), record('c')]))

        records = walker.walk(offset: 0, limit: 10, &pages)

        expect(ids(records)).to eq(%w[a b c])
      end

      it 'keeps records carrying no id rather than deciding they are not records' do
        anonymous = source(page([{ 'email' => 'a@b.test' }, { 'email' => 'c@d.test' }]))
        records = walker.walk(offset: 0, limit: 10, &anonymous)

        expect(records.size).to eq(2)
      end

      it 'returns nothing, and asks nothing, for a limit of zero' do
        records = walker.walk(offset: 0, limit: 0, &source(page([record('a')])))

        expect(records).to be_empty
        expect(asked).to be_empty
      end

      it 'reads an offset past the end as an empty window rather than an error' do
        records = walker.walk(offset: 50, limit: 10, &source(page([record('a')])))

        expect(records).to be_empty
      end

      it 'treats a negative offset as the beginning' do
        records = walker.walk(offset: -5, limit: 1, &source(page([record('a')])))

        expect(ids(records)).to eq(%w[a])
      end

      describe 'a limit of nil, which asks for everything past the offset' do
        it 'walks to the end' do
          pages = source(page([record('a')], next_cursor: 'c1'), page([record('b')]))

          expect(ids(walker.walk(offset: 0, limit: nil, &pages))).to eq(%w[a b])
        end

        it 'asks for the largest page Intercom accepts' do
          walker.walk(offset: 0, limit: nil, &source(page([record('a')])))

          expect(asked.first.first).to eq(Client::MAX_PER_PAGE)
        end
      end

      describe 'caps' do
        before { allow(ForestAdminDatasourceIntercom.logger).to receive(:warn) }

        it 'stops after the page it is allowed, and says the result is truncated' do
          capped = described_class.new(max_pages: 2)
          pages = source(page([record('a')], next_cursor: 'c1'),
                         page([record('b')], next_cursor: 'c2'),
                         page([record('c')], next_cursor: 'c3'))

          capped.walk(offset: 0, limit: nil, &pages)

          expect(asked.size).to eq(2)
          expect(ForestAdminDatasourceIntercom.logger).to have_received(:warn).with(/truncated/)
        end

        it 'stops on the record budget, and never asks for more than it has left' do
          capped = described_class.new(max_records: 3)
          pages = source(page([record('a'), record('b')], next_cursor: 'c1'),
                         page([record('c'), record('d')], next_cursor: 'c2'))

          capped.walk(offset: 0, limit: nil, &pages)

          expect(asked).to eq([[3, nil], [1, 'c1']])
        end

        # A walk that covered the window it was given hands back exactly that,
        # and has nothing to report -- unlike one a cap cut short.
        it 'stays quiet when the window was covered' do
          walker.walk(offset: 0, limit: 1, &source(page([record('a')], next_cursor: 'c1')))

          expect(ForestAdminDatasourceIntercom.logger).not_to have_received(:warn)
        end
      end
    end
  end
end
