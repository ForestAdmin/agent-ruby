require 'json'

module ForestAdminAgent
  module Utils
    class ContextVariablesInjector
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
      include ForestAdminAgent::Builder

      REGEX = /{{([^}]+)}}/
      FULL_REFERENCE_REGEX = /\A{{([^}]+)}}\z/
      COMMENT_MARKERS = ['--', '/*'].freeze

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

        state = { binds: [], replacements: {}, reusable: nil }

        injected_query = query.gsub(REGEX) do
          key = ::Regexp.last_match(1)
          raise_unless_live_sql(key, ::Regexp.last_match.pre_match)
          resolve_bind_symbol(key, datasource, connection_name, context_variables, state)
        end

        [injected_query, state[:binds]]
      end

      # A repeated key's bind can be reused (true, e.g. postgres' $N) or needs a fresh slot per
      # occurrence (false, e.g. "?", purely positional) - unknown until the first repeat, since
      # build_binding_symbol can't declare it upfront. Reusing when unsafe drops a bind value a
      # positional driver needs; always assuming fresh costs an extra RPC round-trip.
      def self.resolve_bind_symbol(key, datasource, connection_name, context_variables, state)
        if state[:replacements].key?(key)
          if state[:reusable].nil?
            probe = datasource.build_binding_symbol(connection_name, state[:binds])
            state[:reusable] = (probe != state[:replacements][key])
          end

          state[:binds] << context_variables.get_value(key) unless state[:reusable]
          state[:replacements][key]
        else
          symbol = datasource.build_binding_symbol(connection_name, state[:binds])
          state[:binds] << context_variables.get_value(key)
          state[:replacements][key] = symbol
        end
      end

      # A placeholder inside a quoted string, a "quoted identifier", or a SQL comment can never
      # be a real bind, so scan everything before the match for one. Both quote styles share the
      # same escape convention (a doubled quote character, never a boundary) so one `quote`
      # variable tracks whichever is currently open. Comments are skipped wholesale rather than
      # scanned char by char - a naive quote count would misfire on an apostrophe inside one (e.g.
      # -- user's note).
      def self.sql_context_before(text)
        quote = nil
        i = 0

        while i < text.length
          if quote
            if text[i] == quote && text[i + 1] == quote
              i += 1
            elsif text[i] == quote
              quote = nil
            end
          elsif /['"]/.match?(text[i])
            quote = text[i]
          elsif COMMENT_MARKERS.include?(text[i, 2])
            i = skip_sql_comment(text, i)
            return :comment if i.nil?

            next
          end

          i += 1
        end

        return :code unless quote

        quote == "'" ? :string : :identifier
      end

      def self.skip_sql_comment(text, index)
        return text.index("\n", index)&.succ if text[index, 2] == '--'

        text.index('*/', index + 2)&.succ&.succ
      end

      PLACEHOLDER_CONTEXT_ERRORS = {
        string: 'is inside a quoted string literal, which native query bindings do not support',
        comment: 'is inside a SQL comment, which native query bindings do not support',
        identifier: 'is inside a quoted identifier - a bind can only ever be a value, never a column or table name'
      }.freeze

      def self.raise_unless_live_sql(key, text_before_match)
        context = sql_context_before(text_before_match)
        return if context == :code

        raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "The '{{#{key}}}' placeholder #{PLACEHOLDER_CONTEXT_ERRORS[context]}."
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
