module ForestAdminDatasourceActiveRecord
  class Collection < ForestAdminDatasourceToolkit::Collection
    def initialize(datasource, model)
      @model = model
      name = model.name.split('::').last
      super(datasource, name)
      fetch_fields
    end

    private

    def fetch_fields
      @model.columns_hash.each do |column_name, column|
        # todo check is not sti column
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(column),
        # filter_operators: [],
          is_primary_key: column_name == @model.primary_key,
          is_read_only: false,
          is_sortable: true,
          # default_value: column.default,
          # enum_values: get_enum_values(column),
          # validations: get_validations(column)
        )

        add_field(column_name, field)
      end
    end

    def get_column_type(column)
      case column.type
      when :boolean
        type = 'Boolean'
      when :datetime
        type = 'Date'
      when :date
        type = 'Dateonly'
      when :integer, :float, :decimal
        type = 'Number'
      when :json, :jsonb, :hstore
        type = 'Json'
      when :string, :text, :citext
        type = 'String'
      when :time
        type = 'Time'
      when :uuid
        type = 'Uuid'
      end

      is_array = (column.respond_to?(:array) && column.array == true)
      is_array ? "[#{type}]" : type
    end

    def get_enum_values(column)
      enum_values = []
      if get_column_type(column) == 'Enum'
        if sti_column?(column)
          @model.descendants.each { |sti_model| enum_values << sti_model.name }
        else
          @model.defined_enums[column.name].each { |name, value| enum_values << name }
        end
      end
      enum_values
    end

    def sti_column?(column)
      @model.inheritance_column && column.name == @model.inheritance_column
    end

    def get_validations(colunm)
      validations = []
      # NOTICE: Do not consider validations if a before_validation Active Records
      #         Callback is detected.
      return validations if @model._validation_callbacks.map(&:kind).include? :before

      if @model._validators? && @model._validators[column.name.to_sym].size > 0
        @model._validators[column.name.to_sym].each do |validator|
          # NOTICE: Do not consider conditional validations
          next if validator.options[:if] || validator.options[:unless] || validator.options[:on]

          case validator
          when ActiveRecord::Validations::PresenceValidator
            validations << {
              type: 'is present',
              message: validator.options[:message]
            }
          when ActiveModel::Validations::NumericalityValidator
            validator.options.each do |option, value|
              case option
              when :greater_than, :greater_than_or_equal_to
                validations << {
                  type: 'is greater than',
                  value: value,
                  message: validator.options[:message]
                }
              when :less_than, :less_than_or_equal_to
                validations << {
                  type: 'is less than',
                  value: value,
                  message: validator.options[:message]
                }
              end
            end
          when ActiveModel::Validations::LengthValidator
            if get_column_type(column) == 'String'
              validator.options.each do |option, value|
                case option
                when :minimum
                  validations << {
                    type: 'is longer than',
                    value: value,
                    message: validator.options[:message]
                  }
                when :maximum
                  validations << {
                    type: 'is shorter than',
                    value: value,
                    message: validator.options[:message]
                  }
                when :is
                  validations << {
                    type: 'is longer than',
                    value: value,
                    message: validator.options[:message]
                  }
                  validations << {
                    type: 'is shorter than',
                    value: value,
                    message: validator.options[:message]
                  }
                end
              end
            end
          when ActiveModel::Validations::FormatValidator
            validator.options.each do |option, value|
              case option
              when :with
                options = /\?([imx]){0,3}/.match(validator.options[:with].to_s)
                options = options && options[1] ? options[1] : ''
                regex = value.source

                # NOTICE: Transform a Ruby regex into a JS one
                regex = regex.sub('\\A' , '^').sub('\\Z' , '$').sub('\\z' , '$').gsub(/\n+|\s+/, '')

                validations << {
                  type: 'is like',
                  value: "/#{regex}/#{options}",
                  message: validator.options[:message]
                }
              end
            end
          end
        end
      end

      validations
    end
  end
end
