require 'spec_helper'

RSpec.describe ForestAdminDatasourceSnowflake::Utils::Identifier do
  describe '.quote' do
    it 'wraps barewords in double quotes' do
      expect(described_class.quote('billing_usage')).to eq('"billing_usage"')
    end

    it 'preserves the case of the input (Snowflake folding only applies to UNquoted)' do
      expect(described_class.quote('BILLING_USAGE')).to eq('"BILLING_USAGE"')
      expect(described_class.quote('Billing_Usage')).to eq('"Billing_Usage"')
    end

    it 'escapes embedded double quotes by doubling them' do
      expect(described_class.quote('weird"name')).to eq('"weird""name"')
    end

    it 'accepts symbols and stringifies them first' do
      expect(described_class.quote(:id)).to eq('"id"')
    end

    it "passes the literal '*' through unmodified for SELECT */COUNT(*)" do
      expect(described_class.quote('*')).to eq('*')
    end
  end
end
