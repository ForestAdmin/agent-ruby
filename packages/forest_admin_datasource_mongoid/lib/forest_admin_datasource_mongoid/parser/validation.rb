module ForestAdminDatasourceMongoid
  module Parser
    module Validation
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      def get_validations(model, column)
        return [] if column.is_a?(Hash)
        return [] if before_validation_callback?(model)
        return [] unless model._validators? && model._validators[column.name.to_sym].size.positive?

        parse_column_validators(model._validators[column.name.to_sym], column)
      end

      def before_validation_callback?(model)
        default_callback_excluded = [:normalize_changed_in_place_attributes]
        model._validation_callbacks.any? do |callback|
          !default_callback_excluded.include?(callback.filter) && callback.kind == :before
        end
      end

      def parse_column_validators(validators, column)
        validations = []
        validators.each do |validator|
          next if validator.options[:if] || validator.options[:unless] || validator.options[:on]

          case validator.class.to_s
          when Mongoid::Validatable::PresenceValidator.to_s
            validations << { operator: Operators::PRESENT }
          when ActiveModel::Validations::NumericalityValidator.to_s
            validations = parse_numericality_validator(validator, validations)
          when Mongoid::Validatable::LengthValidator.to_s
            validations = parse_length_validator(validator, validations, column)
          when Mongoid::Validatable::FormatValidator.to_s
            validations = parse_format_validator(validator, validations)
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
          end
        end

        parsed_validations
      end

      def parse_length_validator(validator, parsed_validations, column)
        return unless get_column_type(column) == 'String'

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
