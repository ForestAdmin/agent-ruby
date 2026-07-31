require 'json'

module ForestAdminAgent
  module Utils
    class ContextVariablesInjector
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
      include ForestAdminAgent::Builder

      REGEX = /{{([^}]+)}}/
      FULL_REFERENCE_REGEX = /\A{{([^}]+)}}\z/

      def self.inject_context_in_value(value, context_variables)
        return value unless value.is_a?(String)

        # A value that is exactly one {{variable}} reference (no surrounding text) keeps the
        # resolved object as-is, so a jsonb/array field gets typed-cast correctly by the
        # datasource instead of being compared against a serialized string that can never match.
        full_reference = FULL_REFERENCE_REGEX.match(value)
        return context_variables.get_value(full_reference[1]) if full_reference

        inject_context_in_value_custom(value) do |context_variable_key|
          resolved_value = context_variables.get_value(context_variable_key)
          if resolved_value.is_a?(Array) || resolved_value.is_a?(Hash)
            JSON.generate(resolved_value)
          else
            resolved_value.to_s
          end
        end
      end

      def self.inject_context_in_native_query(datasource, connection_name, query, context_variables)
        return query unless query.is_a?(String)

        query_with_context_variables_injected = query
        encountered_variables = {}

        while (match = REGEX.match(query_with_context_variables_injected))
          context_variable_key = match[1]

          next if encountered_variables.value?(context_variable_key)

          index = datasource.build_binding_symbol(connection_name, encountered_variables)
          query_with_context_variables_injected.gsub!(
            /{{#{context_variable_key}}}/,
            index
          )
          encountered_variables[index] = context_variables.get_value(context_variable_key)
        end

        [query_with_context_variables_injected, encountered_variables]
      end

      def self.inject_context_in_value_custom(value)
        return value unless value.is_a?(String)

        value_with_context_variables_injected = value
        encountered_variables = []

        while (match = REGEX.match(value_with_context_variables_injected))
          context_variable_key = match[1]

          unless encountered_variables.include?(context_variable_key)
            replacement = yield(context_variable_key)
            value_with_context_variables_injected.gsub!(/{{#{context_variable_key}}}/) { replacement }
          end

          encountered_variables.push(context_variable_key)
        end

        value_with_context_variables_injected
      end

      def self.inject_context_in_filter(filter, context_variables)
        return nil unless filter

        if filter.is_a?(ConditionTreeBranch)
          return ConditionTreeBranch.new(
            filter.aggregator,
            filter.conditions.map { |condition| inject_context_in_filter(condition, context_variables) }
          )
        end

        ConditionTreeLeaf.new(
          filter.field,
          filter.operator,
          inject_context_in_value(filter.value, context_variables)
        )
      end
    end
  end
end
