require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    RSpec.describe Helpers do
      let(:helpers_module) { Class.new { include Helpers }.new }

      it 'replace dots by underscores' do
        expect(helpers_module.escape('a.b.c')).to eq('a_b_c')
      end

      it 'recursivelies set a value in a plain object' do
        obj = {}
        helpers_module.recursive_set(obj, 'a.b.c', 1)
        helpers_module.recursive_set(obj, 'a.b.d', 2)
        expect(obj).to eq({ 'a' => { 'b' => { 'c' => 1, 'd' => 2 } } })
      end

      it 'compares using both ordinal and lexicographical order' do
        expect(helpers_module.compare_ids('a', 'a')).to eq(0)

        expect(helpers_module.compare_ids('a', 'b')).to be.negative?
        expect(helpers_module.compare_ids('b', 'a')).to be.positive?

        expect(helpers_module.compare_ids('a', 'a.b')).to be.negative?
        expect(helpers_module.compare_ids('a.b', 'a')).to be.positive?

        expect(helpers_module.compare_ids('a.2.b', 'a.10.a')).to be.negative?
        expect(helpers_module.compare_ids('a.10.a', 'a.2.b')).to be.positive?
      end

      it 'splitId should separate rootId and path' do
        expect(helpers_module.split_id('a.b.c')).to eq(['a', 'b.c'])

        expect(helpers_module.split_id('5a934e000102030405000000.c')).to eq([BSON::ObjectId('5a934e000102030405000000'), 'c'])
      end

      it 'regroup rootIds by path' do
        groups = helpers_module.group_ids_by_path(['a.b.c', 'b.b.c', 'a.b.d'])

        expect(groups).to eq({ 'b.c' => ['a', 'b'], 'b.d' => ['a'] })
      end

      it 'replaceMongoTypes should replace objectids, decimal128 and dates by strings' do
        record = helpers_module.replace_mongo_types({
                                                      nested: [
                                                        {
                                                          _id: BSON::ObjectId.from_string('5a934e000102030405000000'),
                                                          date: Time.new(1985, 10, 26, 1, 22, 0, '-08:00'),
                                                          price: BSON::Decimal128.new('42')
                                                        }
                                                      ]
                                                    })

        expect(record).to eq({ nested: [{ _id: '5a934e000102030405000000', date: '1985-10-26T01:22:00-08:00', price: '42' }] })
      end
    end
  end
end
