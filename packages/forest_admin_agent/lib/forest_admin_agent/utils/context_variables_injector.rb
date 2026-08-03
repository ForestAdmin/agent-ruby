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
          serialize_for_injection(context_variables.get_value(context_variable_key))
        end
      end

      def self.serialize_for_injection(resolved_value)
        return JSON.generate(resolved_value) if resolved_value.is_a?(Array) || resolved_value.is_a?(Hash)

        resolved_value.to_s
      end

      def self.inject_context_in_native_query(datasource, connection_name, query, context_variables)
        return query unless query.is_a?(String)

        binds = []
        # One bind per occurrence, not per distinct key: positional ("?") drivers consume one
        # bind slot per placeholder in the query text, even when the same {{key}} repeats, so
        # reusing a single slot for a repeated key (safe for numbered $N placeholders) would
        # leave a positional driver with fewer bind values than placeholders.
        injected_query = query.gsub(REGEX) do
          key = ::Regexp.last_match(1)
          symbol = datasource.build_binding_symbol(connection_name, binds)
          binds << context_variables.get_value(key)
          symbol
        end

        [injected_query, binds]
      end

      def self.inject_context_in_value_custom(value)
        return value unless value.is_a?(String)

        # Resolve every distinct {{key}} found in the ORIGINAL string upfront, then substitute
        # in a single gsub pass. A resolved value can itself contain "{{...}}"-looking text (e.g.
        # a tag whose data happens to include it); re-scanning a mutated string for placeholders
        # (the previous while+gsub! approach) would misinterpret that text as a new reference, or
        # loop forever if it matched an already-resolved key without ever changing the string.
        keys = value.scan(REGEX).map(&:first).uniq
        return value if keys.empty?

        replacements = keys.to_h { |key| [key, yield(key)] }

        value.gsub(REGEX) { replacements[::Regexp.last_match(1)] }
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
