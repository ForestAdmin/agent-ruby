require 'spec_helper'

module ForestAdminDatasourceToolkit
  describe Collection do
    before do
      @field = Schema::ColumnSchema.new(column_type: 'String')
      @datasource = Datasource.new
      @collection = described_class.new(@datasource, '__collection__')
    end

    describe 'is_countable' do
      it 'return false when value is not override' do
        expect(@collection.is_countable?).to be false
      end

      it 'return true when value is override' do
        @collection.schema[:countable] = true
        expect(@collection.is_countable?).to be true
      end
    end

    describe 'is_searchable' do
      it 'return false when value is not override' do
        expect(@collection.is_searchable?).to be false
      end

      it 'return true when value is override' do
        @collection.schema[:searchable] = true
        expect(@collection.is_searchable?).to be true
      end
    end

    describe 'add_field' do
      it 'raise when a field with the same name already exist' do
        expect do
          @collection.add_field('__duplicated__', @field)
          @collection.add_field('__duplicated__', @field)
        end.to raise_error(
          ForestAdminDatasourceToolkit::Exceptions::ForestException,
          '🌳🌳🌳 Field __duplicated__ already defined in collection'
        )
      end

      it 'add field with unique name' do
        @collection.add_field('__field__', @field)

        expect(@collection.schema[:fields]).to eq({ '__field__' => @field })
      end
    end

    describe 'add_fields' do
      it 'add all fields with unique name' do
        @collection.add_fields(
          {
            __first__: @field,
            __second__: @field
          }
        )

        expect(@collection.schema[:fields]).to eq(
          {
            __first__: @field,
            __second__: @field
          }
        )
      end
    end

    describe 'enable_count' do
      it 'set at true the countable option' do
        expect(@collection.is_countable?).to be false

        @collection.enable_count

        expect(@collection.is_countable?).to be true
      end
    end

    describe 'enable_search' do
      it 'set at true the searchable option' do
        expect(@collection.is_searchable?).to be false

        @collection.enable_search

        expect(@collection.is_searchable?).to be true
      end
    end

    describe 'add_segments' do
      it 'add segments into the schema' do
        @collection.add_segments(%w[segment_1 segment_2])

        expect(@collection.schema[:segments]).to eq(%w[segment_1 segment_2])
      end

      it 'add segments into the schema with existing segments' do
        @collection.add_segments(%w[segment_1 segment_2])
        @collection.add_segments(%w[segment_3])

        expect(@collection.schema[:segments]).to eq(%w[segment_1 segment_2 segment_3])
      end
    end
  end
end
