module ForestAdminDatasourceActiveRecord
  module Parser
    module Validation
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      def get_validations(column)
        validations = []
        # NOTICE: Do not consider validations if a before_validation Active Records
        #         Callback is detected.
        return validations if @model._validation_callbacks.map(&:kind).include? :before

        if @model._validators? && @model._validators[column.name.to_sym].size.positive?
          @model._validators[column.name.to_sym].each do |validator|
            # NOTICE: Do not consider conditional validations
            next if validator.options[:if] || validator.options[:unless] || validator.options[:on]

            case validator
            when ActiveRecord::Validations::PresenceValidator
              validations << { operator: Operators::PRESENT }
            when ActiveModel::Validations::NumericalityValidator
              validations = parse_numericality_validator(validator, validations)
            when ActiveModel::Validations::LengthValidator
              validations = parse_length_validator(validator, validations)
            when ActiveModel::Validations::FormatValidator
              validations = parse_format_validator(validator, validations)
            end
          end
        end

        validations
      end

      def parse_numericality_validator(validator, parsed_validations)
        validator.options.each do |option, value|
          case option
          when :greater_than, :greater_than_or_equal_to
            parsed_validations << { operator: Operators::GREATER_THAN, value: value }
          when :less_than, :less_than_or_equal_to
            parsed_validations << { operator: Operators::LESS_THAN, value: value }
          when :allow_nil
            parsed_validations << { operator: Operators::PRESENT } unless value
          end
        end

        parsed_validations
      end

      def parse_length_validator(validator, parsed_validations)
        return unless get_column_type(@model, column) == 'String'

        validator.options.each do |option, value|
          case option
          when :minimum
            parsed_validations << { operator: Operators::LONGER_THAN, value: value }
          when :maximum
            parsed_validations << { operator: Operators::SHORTER_THAN, value: value }
          when :is
            parsed_validations << { operator: Operators::LONGER_THAN, value: value }
            parsed_validations << { operator: Operators::SHORTER_THAN, value: value }
          end
        end

        parsed_validations
      end

      def parse_format_validator(validator, parsed_validations)
        validator.options.each do |option, value|
          case option
          when :with
            options = /\?([imx]){0,3}/.match(validator.options[:with].to_s)
            options = options && options[1] ? options[1] : ''
            regex = value.source

            # NOTICE: Transform a Ruby regex into a JS one
            regex = regex.sub('\\A', '^').sub('\\Z', '$').sub('\\z', '$').gsub(/\n+|\s+/, '')

            parsed_validations << { operator: Operators::CONTAINS, value: "/#{regex}/#{options}" }
          end
        end

        parsed_validations
      end
    end
  end
end
