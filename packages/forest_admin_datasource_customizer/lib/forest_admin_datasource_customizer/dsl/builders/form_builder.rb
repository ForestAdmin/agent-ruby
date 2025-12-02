# frozen_string_literal: true

module ForestAdminDatasourceCustomizer
  module DSL
    # FormBuilder provides a fluent DSL for building action forms
    #
    # @example
    #   form do
    #     field :email, type: :string, widget: 'TextInput'
    #     field :age, type: :number
    #     field :photo, type: :file
    #
    #     page do
    #       field :address, type: :string
    #       field :city, type: :string
    #     end
    #   end
    class FormBuilder
      attr_reader :fields

      def initialize
        @fields = []
      end

      # Add a field to the form
      # @param name [String, Symbol] field name
      # @param type [String, Symbol] field type (:string, :number, :boolean, :date, :file, etc.)
      # @param widget [String] optional widget type
      # @param options [Array<Hash>] options for dropdown/radio widgets
      # @param readonly [Boolean] whether field is read-only
      # @param default [Object] default value
      # @param description [String] field description
      # @param placeholder [String] placeholder text
      # @param block [Proc] optional proc for computed values
      def field(name, type:, widget: nil, options: nil, readonly: false, default: nil,
                description: nil, placeholder: nil, &block)
        field_def = {
          label: name.to_s,
          type: normalize_type(type)
        }

        field_def[:widget] = widget if widget
        field_def[:options] = options if options
        field_def[:is_read_only] = readonly if readonly
        field_def[:default_value] = default if default
        field_def[:description] = description if description
        field_def[:placeholder] = placeholder if placeholder
        field_def[:value] = block if block

        @fields << field_def
      end

      # Add a page layout to group fields
      # @param block [Proc] block containing nested fields
      def page(&block)
        page_builder = FormBuilder.new
        page_builder.instance_eval(&block)

        @fields << {
          type: 'Layout',
          component: 'Page',
          elements: page_builder.fields
        }
      end

      # Add a row layout to arrange fields horizontally
      # @param block [Proc] block containing nested fields
      def row(&block)
        row_builder = FormBuilder.new
        row_builder.instance_eval(&block)

        @fields << {
          type: 'Layout',
          component: 'Row',
          fields: row_builder.fields
        }
      end

      # Add a separator
      def separator
        @fields << { type: 'Layout', component: 'Separator' }
      end

      # Add a HTML block
      # @param content [String] HTML content
      def html(content)
        @fields << {
          type: 'Layout',
          component: 'HtmlBlock',
          content: content
        }
      end

      private

      # Normalize type symbols to Forest Admin type strings
      # @param type [String, Symbol] the type
      # @return [String] normalized type
      def normalize_type(type)
        type_map = {
          string: 'String',
          number: 'Number',
          integer: 'Number',
          boolean: 'Boolean',
          date: 'Date',
          datetime: 'Date',
          time: 'Time',
          json: 'Json',
          file: 'File',
          enum: 'Enum'
        }

        type_sym = type.to_s.downcase.to_sym
        type_map[type_sym] || type.to_s
      end
    end
  end
end
