RSpec.describe ForestAdminDatasourcePylon::Pagination::CursorWalker do
  let(:calls) { [] }

  def search_page(ids, next_cursor)
    ForestAdminDatasourcePylon::Client::SearchPage.new(
      records: ids.map { |id| { 'id' => id } }, next_cursor: next_cursor
    )
  end

  # Serves `pages` in order and records the (limit, cursor) each call was made
  # with, so a spec can assert on how the walk was driven.
  def source(pages)
    proc do |limit, cursor|
      calls << { limit: limit, cursor: cursor }
      pages.fetch(calls.size - 1, search_page([], nil))
    end
  end

  def walk(pages, offset:, limit:, walker: described_class.new)
    walker.walk(offset: offset, limit: limit, &source(pages))
  end

  it 'returns the records of a single page when it covers the window' do
    records = walk([search_page(%w[a b c], nil)], offset: 0, limit: 3)

    expect(records).to eq([{ 'id' => 'a' }, { 'id' => 'b' }, { 'id' => 'c' }])
    expect(calls).to eq([{ limit: 3, cursor: nil }])
  end

  it 'walks pages until the window is covered, then slices off the offset' do
    pages = [search_page(%w[a b], 'c1'), search_page(%w[c d], 'c2'), search_page(%w[e f], nil)]

    expect(walk(pages, offset: 4, limit: 2)).to eq([{ 'id' => 'e' }, { 'id' => 'f' }])
    expect(calls.map { |call| call[:cursor] }).to eq([nil, 'c1', 'c2'])
  end

  it 'asks only for what is still missing on each page' do
    pages = [search_page(%w[a b], 'c1'), search_page(%w[c], 'c2'), search_page(%w[d], nil)]

    walk(pages, offset: 0, limit: 4)

    expect(calls.map { |call| call[:limit] }).to eq([4, 2, 1])
  end

  it 'never requests more than the API maximum in one call' do
    walk([search_page(%w[a], nil)], offset: 0, limit: 50_000)

    expect(calls.first[:limit]).to eq(ForestAdminDatasourcePylon::Client::MAX_SEARCH_LIMIT)
  end

  it 'stops at the last page and returns fewer records than asked' do
    expect(walk([search_page(%w[a b], nil)], offset: 0, limit: 10).size).to eq(2)
    expect(calls.size).to eq(1)
  end

  it 'returns an empty window when the offset is past the end' do
    expect(walk([search_page(%w[a b], nil)], offset: 50, limit: 10)).to eq([])
  end

  it 'fetches nothing when the limit is not positive' do
    expect(walk([search_page(%w[a], nil)], offset: 0, limit: 0)).to eq([])
    expect(calls).to be_empty
  end

  describe 'a nil limit' do
    it 'walks every page the API hands out instead of stopping at one window' do
      pages = [search_page(%w[a b], 'c1'), search_page(%w[c d], 'c2'), search_page(%w[e], nil)]

      expect(walk(pages, offset: 0, limit: nil).size).to eq(5)
      expect(calls.size).to eq(3)
    end

    it 'asks for the whole record budget on each page' do
      walk([search_page(%w[a], nil)], offset: 0, limit: nil)

      expect(calls.first[:limit]).to eq(ForestAdminDatasourcePylon::Client::MAX_SEARCH_LIMIT)
    end

    it 'still drops the offset' do
      pages = [search_page(%w[a b c], 'c1'), search_page(%w[d], nil)]

      expect(walk(pages, offset: 2, limit: nil)).to eq([{ 'id' => 'c' }, { 'id' => 'd' }])
    end

    it 'costs a single request when the first page is the last' do
      expect(walk([search_page(%w[a b], nil)], offset: 0, limit: nil).size).to eq(2)
      expect(calls.size).to eq(1)
    end
  end

  describe 'truncation' do
    before { allow(ForestAdminDatasourcePylon.logger).to receive(:warn) }

    it 'stops at the page cap and logs a warning' do
      pages = Array.new(5) { |i| search_page(["r#{i}"], "c#{i}") }

      expect(walk(pages, offset: 0, limit: 100, walker: described_class.new(max_pages: 3)).size).to eq(3)
      expect(calls.size).to eq(3)
      expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/Stopped paginating after 3 page/)
    end

    it 'stops at the record cap and logs a warning' do
      pages = Array.new(5) { |i| search_page(%W[a#{i} b#{i}], "c#{i}") }

      expect(walk(pages, offset: 0, limit: 100, walker: described_class.new(max_records: 4)).size).to eq(4)
      expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/4 record\(s\)/)
    end

    it 'never asks for more than the remaining record budget' do
      pages = [search_page(%w[a b], 'c1'), search_page(%w[c], 'c2')]

      walk(pages, offset: 0, limit: 100, walker: described_class.new(max_records: 3))

      expect(calls.map { |call| call[:limit] }).to eq([3, 1])
    end

    it 'does not warn when the walk ends naturally' do
      walk([search_page(%w[a b], nil)], offset: 0, limit: 100)

      expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
    end

    it 'warns when a cap cuts a walk that asked for every record' do
      pages = Array.new(5) { |i| search_page(%W[a#{i} b#{i}], "c#{i}") }

      expect(walk(pages, offset: 0, limit: nil, walker: described_class.new(max_records: 4)).size).to eq(4)
      expect(ForestAdminDatasourcePylon.logger)
        .to have_received(:warn).with(/every record past offset=0; results are truncated/)
    end

    it 'does not warn when a window the caller asked for is covered exactly' do
      pages = [search_page(%w[a b], 'c1'), search_page(%w[c d], 'c2')]

      expect(walk(pages, offset: 0, limit: 2).size).to eq(2)
      expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
    end
  end

  describe 'defensive stops' do
    it 'stops when a page comes back empty despite advertising a next page' do
      pages = [search_page([], 'c1'), search_page(%w[a], 'c2')]

      expect(walk(pages, offset: 0, limit: 10)).to eq([])
      expect(calls.size).to eq(1)
    end

    it 'stops when the cursor does not advance' do
      pages = [search_page(%w[a], 'same'), search_page(%w[b], 'same'), search_page(%w[c], 'same')]

      expect(walk(pages, offset: 0, limit: 10).size).to eq(2)
      expect(calls.size).to eq(2)
    end
  end
end
