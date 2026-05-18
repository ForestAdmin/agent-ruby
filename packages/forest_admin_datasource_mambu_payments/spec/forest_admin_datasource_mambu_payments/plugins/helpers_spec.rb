RSpec.describe ForestAdminDatasourceMambuPayments::Plugins::Helpers do
  let(:described) { described_class }

  describe '.normalize_scopes' do
    it 'defaults to both single and bulk when value is nil' do
      expect(described.normalize_scopes(nil)).to contain_exactly(:single, :bulk)
    end

    it 'accepts strings and symbols interchangeably' do
      expect(described.normalize_scopes(%w[single])).to eq([:single])
      expect(described.normalize_scopes([:bulk])).to eq([:bulk])
    end

    it 'dedupes repeated values' do
      expect(described.normalize_scopes(%i[single single bulk])).to contain_exactly(:single, :bulk)
    end

    it 'raises a ForestException on unknown scopes' do
      expect { described.normalize_scopes(%i[single global]) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /Unknown scopes: global/)
    end
  end

  describe '.resolve_ids' do
    let(:context) { ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(records: records) }

    context 'with a list of records' do
      let(:records) { [{ 'foo_id' => 'a' }, { 'foo_id' => 'b' }] }

      it 'returns the value of the configured field for each record' do
        expect(described.resolve_ids(context, 'foo_id')).to eq(%w[a b])
      end
    end

    it 'accepts symbol keys on the host record' do
      records = [{ foo_id: 'sym' }]
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(records: records)
      expect(described.resolve_ids(context, 'foo_id')).to eq(['sym'])
    end

    it 'skips records without a value (nil or missing)' do
      records = [{ 'foo_id' => 'a' }, { 'foo_id' => nil }, { 'other' => 'b' }]
      context = ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(records: records)
      expect(described.resolve_ids(context, 'foo_id')).to eq(['a'])
    end

    it 'logs and returns [] when get_records raises' do
      ctx = instance_double(ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle)
      allow(ctx).to receive(:get_records).and_raise(StandardError, 'boom')
      allow(ForestAdminDatasourceMambuPayments.logger).to receive(:warn)

      expect(described.resolve_ids(ctx, 'foo_id')).to eq([])
      expect(ForestAdminDatasourceMambuPayments.logger).to have_received(:warn)
        .with(a_string_including('foo_id', 'boom'))
    end
  end

  describe '.each_with_rescue' do
    it 'yields once per id and returns succeeded/failed splits' do
      succeeded, failed = described.each_with_rescue(%w[a b c], 'op') { |id| raise StandardError, 'x' if id == 'b' }
      expect(succeeded).to eq(%w[a c])
      expect(failed.map(&:first)).to eq(%w[b])
    end

    it 'logs failures with class and message' do
      allow(ForestAdminDatasourceMambuPayments.logger).to receive(:warn)
      described.each_with_rescue(['x'], 'op') { raise StandardError, 'boom' } # rubocop:disable Lint/UnreachableLoop
      expect(ForestAdminDatasourceMambuPayments.logger).to have_received(:warn)
        .with(a_string_including('op', '#x', 'boom'))
    end
  end

  describe '.to_int' do
    it 'parses integer strings' do
      expect(described.to_int('42')).to eq(42)
    end

    it 'returns nil for blank or non-numeric values' do
      expect(described.to_int(nil)).to be_nil
      expect(described.to_int('')).to be_nil
      expect(described.to_int('not a number')).to be_nil
    end
  end

  describe '.write_back' do
    let(:collection) { instance_double('Collection', update: true) } # rubocop:disable RSpec/VerifiedDoubleReference
    let(:context) do
      ForestAdminDatasourceMambuPayments::PluginSupport::FakeContext.new(
        collection: collection, filter: :stub_filter
      )
    end

    it 'returns :skipped when the field or value is nil' do
      expect(described.write_back(context, nil, 'v')).to eq(:skipped)
      expect(described.write_back(context, 'field', nil)).to eq(:skipped)
    end

    it 'calls collection.update with the right payload on success' do
      expect(described.write_back(context, 'mambu_id', 'abc')).to eq(:ok)
      expect(collection).to have_received(:update).with(:stub_filter, { 'mambu_id' => 'abc' })
    end

    it 'logs and returns [:failed, msg] when update raises' do
      allow(collection).to receive(:update).and_raise(StandardError, 'db down')
      allow(ForestAdminDatasourceMambuPayments.logger).to receive(:warn)

      result = described.write_back(context, 'mambu_id', 'abc')
      expect(result.first).to eq(:failed)
      expect(result.last).to include('db down')
      expect(ForestAdminDatasourceMambuPayments.logger).to have_received(:warn).with(a_string_including('mambu_id'))
    end
  end
end
