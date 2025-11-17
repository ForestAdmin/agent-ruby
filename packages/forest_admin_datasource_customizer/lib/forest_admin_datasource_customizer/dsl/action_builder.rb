# frozen_string_literal: true

module ForestAdminDatasourceCustomizer
  module DSL
    # ActionBuilder provides a fluent DSL for building custom actions
    #
    # @example Simple action
    #   action :approve, scope: :bulk do
    #     execute do
    #       success "Records approved!"
    #     end
    #   end
    #
    # @example Action with form
    #   action :export, scope: :global do
    #     description "Export all data"
    #     generates_file!
    #
    #     form do
    #       field :format, type: :string, widget: 'Dropdown',
    #             options: [{ label: 'CSV', value: 'csv' }]
    #     end
    #
    #     execute do
    #       format = form_value(:format)
    #       file content: generate_csv, name: "export.#{format}"
    #     end
    #   end
    class ActionBuilder
      def initialize(scope:)
        @scope = normalize_scope(scope)
        @form_fields = nil
        @execute_block = nil
        @description = nil
        @submit_button_label = nil
        @generate_file = false
      end

      # Set the action description
      # @param text [String] description text
      def description(text)
        @description = text
      end

      # Set custom submit button label
      # @param label [String] button label
      def submit_button_label(label)
        @submit_button_label = label
      end

      # Mark action as generating a file
      def generates_file!
        @generate_file = true
      end

      # Define the action form using FormBuilder DSL
      # @param block [Proc] block to build the form
      def form(&block)
        form_builder = FormBuilder.new
        form_builder.instance_eval(&block)
        @form_fields = form_builder.fields
      end

      # Define the action execution logic
      # The block is executed in the context of an ExecutionContext
      # which provides helper methods like success, error, file, etc.
      #
      # @param block [Proc] execution block
      def execute(&block)
        @execute_block = proc do |context, result_builder|
          executor = ExecutionContext.new(context, result_builder)
          executor.instance_eval(&block)
          executor.result
        end
      end

      # Build and return the BaseAction instance
      # @return [Decorators::Action::BaseAction] the action
      def to_action
        raise ArgumentError, 'execute block is required' unless @execute_block

        Decorators::Action::BaseAction.new(
          scope: @scope,
          form: @form_fields,
          is_generate_file: @generate_file,
          description: @description,
          submit_button_label: @submit_button_label,
          &@execute_block
        )
      end

      private

      # Normalize scope symbols to ActionScope constants
      # @param scope [String, Symbol] the scope
      # @return [String] normalized scope
      def normalize_scope(scope)
        scope_map = {
          single: Decorators::Action::Types::ActionScope::SINGLE,
          bulk: Decorators::Action::Types::ActionScope::BULK,
          global: Decorators::Action::Types::ActionScope::GLOBAL
        }

        return scope if scope.is_a?(String) && scope_map.value?(scope)

        scope_sym = scope.to_s.downcase.to_sym
        scope_map[scope_sym] || raise(ArgumentError, "Invalid scope: #{scope}")
      end
    end
  end
end
