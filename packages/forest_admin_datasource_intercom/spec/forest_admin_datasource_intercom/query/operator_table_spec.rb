module ForestAdminDatasourceIntercom
  RSpec.describe Query::OperatorTable do
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:rules) { ForestAdminDatasourceToolkit::Validations::Rules }
    let(:equivalent) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeEquivalent }

    def field(type, operators)
      Query::SearchFields::Field.new(column: 'c', field: 'c', type: type, operators: operators, source: 'spec')
    end

    describe '.forest_operators' do
      it 'publishes only what the endpoint accepts on that field' do
        expect(described_class.forest_operators(field('string', ['=']))).to eq([operators::EQUAL])
        expect(described_class.forest_operators(field('string', ['=', '!='])))
          .to eq([operators::EQUAL, operators::NOT_EQUAL])
      end

      # Intercom documents one substring operator and no case semantics for it,
      # and the frontend sends either spelling depending on the column.
      it 'reads both spellings of contains onto the one operator Intercom has' do
        published = described_class.forest_operators(field('text', ['~']))

        expect(published).to eq([operators::CONTAINS, operators::I_CONTAINS])
      end

      # The point of the whole table: a date column carries the two bounds even
      # where the endpoint accepts more, because declaring an equality on a Date
      # makes the toolkit republish `in`, which its own validator refuses.
      it 'keeps a date column to the two bounds whatever the endpoint accepts' do
        published = described_class.forest_operators(field('date', ['>', '<', '>=', '<=', '=', '!=']))

        expect(published).to eq([operators::GREATER_THAN, operators::LESS_THAN])
      end

      it 'publishes nothing for a field the endpoint answers no known operator on' do
        expect(described_class.forest_operators(field('string', ['~']))).to be_empty
      end
    end

    describe '.intercom_operator' do
      it 'spells a Forest operator the way the search DSL does' do
        expect(described_class.intercom_operator(field('number', ['>']), operators::GREATER_THAN)).to eq('>')
      end

      it 'answers nil for an operator the endpoint does not accept on that field' do
        expect(described_class.intercom_operator(field('string', ['=']), operators::NOT_EQUAL)).to be_nil
      end

      it 'answers nil for an operator no field of that type carries' do
        expect(described_class.intercom_operator(field('boolean', ['=']), operators::CONTAINS)).to be_nil
      end
    end

    describe 'the operators every published column ends up with' do
      # The invariant PRD-989 says nothing checks: everything the agent publishes
      # from what a column declares must be an operator its own validator allows.
      # A column advertising a filter the agent then rejects is a 400 in the
      # interface for a reason that has nothing to do with Intercom.
      it 'is a set the toolkit validator allows, for every column of every endpoint' do
        column_types = { 'string' => 'String', 'text' => 'String', 'date' => 'Date',
                         'boolean' => 'Boolean', 'number' => 'Number' }

        Query::SearchFields.endpoints.each do |name|
          Query::SearchFields.fetch(name).fields.each_value do |searchable|
            declared = described_class.forest_operators(searchable)
            column_type = column_types.fetch(searchable.type)
            published = operators.all.select { |o| equivalent.equivalent_tree?(o, declared, column_type) }

            expect(published - rules.get_allowed_operators_for_column_type(column_type))
              .to be_empty, "#{name}.#{searchable.column} publishes an operator Rules refuses"
          end
        end
      end
    end
  end
end
