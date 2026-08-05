require 'spec_helper'

RSpec.describe ForestAdminDatasourceGraphqlHasura::Query::FilterConverter do
  def nodes
    ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
  end

  def operators
    ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
  end

  def leaf(field, operator, value = nil)
    nodes::ConditionTreeLeaf.new(field, operator, value)
  end

  it 'returns nil for a nil tree' do
    expect(described_class.convert(nil)).to be_nil
  end

  it 'converts comparison operators' do
    expect(described_class.convert(leaf('a', operators::EQUAL, 1))).to eq({ 'a' => { '_eq' => 1 } })
    expect(described_class.convert(leaf('a', operators::NOT_EQUAL, 1))).to eq({ 'a' => { '_neq' => 1 } })
    expect(described_class.convert(leaf('a', operators::GREATER_THAN, 1))).to eq({ 'a' => { '_gt' => 1 } })
    expect(described_class.convert(leaf('a', operators::LESS_THAN, 1))).to eq({ 'a' => { '_lt' => 1 } })
    expect(described_class.convert(leaf('a', operators::IN, [1, 2]))).to eq({ 'a' => { '_in' => [1, 2] } })
    expect(described_class.convert(leaf('a', operators::NOT_IN, [1]))).to eq({ 'a' => { '_nin' => [1] } })
  end

  it 'converts null-checking operators' do
    expect(described_class.convert(leaf('a', operators::EQUAL))).to eq({ 'a' => { '_is_null' => true } })
    expect(described_class.convert(leaf('a', operators::PRESENT))).to eq({ 'a' => { '_is_null' => false } })
    expect(described_class.convert(leaf('a', operators::MISSING))).to eq({ 'a' => { '_is_null' => true } })
  end

  it 'converts string operators to case-insensitive like patterns' do
    expect(described_class.convert(leaf('a', operators::CONTAINS, 'x'))).to eq({ 'a' => { '_ilike' => '%x%' } })
    expect(described_class.convert(leaf('a', operators::I_CONTAINS, 'x'))).to eq({ 'a' => { '_ilike' => '%x%' } })
    expect(described_class.convert(leaf('a', operators::STARTS_WITH, 'x'))).to eq({ 'a' => { '_ilike' => 'x%' } })
    expect(described_class.convert(leaf('a', operators::ENDS_WITH, 'x'))).to eq({ 'a' => { '_ilike' => '%x' } })
    expect(described_class.convert(leaf('a', operators::NOT_CONTAINS, 'x'))).to eq({ 'a' => { '_nilike' => '%x%' } })
  end

  it 'escapes LIKE wildcards so a literal % or _ is searched' do
    expect(described_class.convert(leaf('a', operators::CONTAINS, '100%')))
      .to eq({ 'a' => { '_ilike' => '%100\\%%' } })
    expect(described_class.convert(leaf('a', operators::CONTAINS, 'a_b')))
      .to eq({ 'a' => { '_ilike' => '%a\\_b%' } })
    expect(described_class.convert(leaf('a', operators::CONTAINS, 'c:\\x')))
      .to eq({ 'a' => { '_ilike' => '%c:\\\\x%' } })
  end

  # A `String_comparison_exp` has no `_and`/`_or` field, hence the combination
  # one level up.
  it 'converts In/NotIn containing nil into explicit null checks combined at bool_exp level' do
    expect(described_class.convert(leaf('a', operators::IN, [nil, ''])))
      .to eq({ '_or' => [{ 'a' => { '_is_null' => true } }, { 'a' => { '_in' => [''] } }] })
    expect(described_class.convert(leaf('a', operators::NOT_IN, [nil, ''])))
      .to eq({ '_and' => [{ 'a' => { '_is_null' => false } }, { 'a' => { '_nin' => [''] } }] })
    expect(described_class.convert(leaf('a', operators::IN, [nil]))).to eq({ 'a' => { '_is_null' => true } })
    expect(described_class.convert(leaf('a', operators::NOT_IN, [nil]))).to eq({ 'a' => { '_is_null' => false } })
  end

  it 'keeps the relation path on both sides of a null-aware In through a relation' do
    expect(described_class.convert(leaf('membership:full_name', operators::IN, [nil, ''])))
      .to eq({ '_or' => [
               { 'membership' => { 'full_name' => { '_is_null' => true } } },
               { 'membership' => { 'full_name' => { '_in' => [''] } } }
             ] })
  end

  it 'converts nested relation paths to nested bool_exps' do
    expect(described_class.convert(leaf('membership:full_name', operators::EQUAL, 'Jane')))
      .to eq({ 'membership' => { 'full_name' => { '_eq' => 'Jane' } } })
  end

  it 'converts And/Or branches' do
    tree = nodes::ConditionTreeBranch.new('Or', [leaf('a', operators::EQUAL, 1), leaf('b', operators::EQUAL, 2)])

    expect(described_class.convert(tree)).to eq(
      '_or' => [{ 'a' => { '_eq' => 1 } }, { 'b' => { '_eq' => 2 } }]
    )
  end

  # Hasura reads an empty `_and` as vacuously true, which would let a mutation
  # through the empty-filter guard and touch every row.
  it 'converts a branch that matches everything to nil rather than an empty _and' do
    expect(described_class.convert(nodes::ConditionTreeBranch.new('And', []))).to be_nil
    expect(described_class.convert(nodes::ConditionTreeBranch.new('Or', [
                                                                    nodes::ConditionTreeBranch.new('And', []),
                                                                    leaf('a', operators::EQUAL, 1)
                                                                  ]))).to be_nil
  end

  it 'keeps an empty Or, which matches nothing' do
    expect(described_class.convert(nodes::ConditionTreeBranch.new('Or', []))).to eq({ '_or' => [] })
  end

  it 'drops a match-everything branch nested in an And' do
    tree = nodes::ConditionTreeBranch.new('And', [
                                            nodes::ConditionTreeBranch.new('And', []),
                                            leaf('a', operators::EQUAL, 1)
                                          ])

    expect(described_class.convert(tree)).to eq({ '_and' => [{ 'a' => { '_eq' => 1 } }] })
  end

  it 'raises on unsupported operators' do
    expect { described_class.convert(leaf('a', operators::LONGER_THAN, 3)) }
      .to raise_error(ForestAdminDatasourceGraphqlHasura::GraphqlError, /Unsupported operator/)
  end
end
