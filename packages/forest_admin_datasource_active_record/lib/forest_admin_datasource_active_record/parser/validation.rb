module ForestAdminDatasourceActiveRecord
  module Parser
    module Validation
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
              validations << {
                type: 'is present',
                message: validator.options[:message]
              }
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
            parsed_validations << {
              type: 'is greater than',
              value: value,
              message: validator.options[:message]
            }
          when :less_than, :less_than_or_equal_to
            parsed_validations << {
              type: 'is less than',
              value: value,
              message: validator.options[:message]
            }
          end
        end
      end

      def parse_length_validator(validator, parsed_validations)
        return unless get_column_type(column) == 'String'

        validator.options.each do |option, value|
          case option
          when :minimum
            parsed_validations << {
              type: 'is longer than',
              value: value,
              message: validator.options[:message]
            }
          when :maximum
            parsed_validations << {
              type: 'is shorter than',
              value: value,
              message: validator.options[:message]
            }
          when :is
            parsed_validations << {
              type: 'is longer than',
              value: value,
              message: validator.options[:message]
            }
            parsed_validations << {
              type: 'is shorter than',
              value: value,
              message: validator.options[:message]
            }
          end
        end
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

            parsed_validations << {
              type: 'is like',
              value: "/#{regex}/#{options}",
              message: validator.options[:message]
            }
          end
        end

        parsed_validations
      end
    end
  end
end
