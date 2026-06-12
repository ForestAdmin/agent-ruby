module ForestAdminDatasourceMambuPayments
  module Plugins
    # Shared helpers for Mambu Payments plugins: input normalization, host
    # record id resolution, and per-id rescue logic for bulk transitions.
    module Helpers
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope

      SCOPE_KEYS = %i[single bulk].freeze
      SCOPES = { single: ActionScope::SINGLE, bulk: ActionScope::BULK }.freeze

      module_function

      # Relation plugins must be installed at the datasource level
      # (`@agent.use(plugin, {})`) so they can customize several collections at
      # once. Raises a clear error when a caller installs one on a single
      # collection instead.
      def require_datasource!(datasource_customizer, plugin_class)
        return if datasource_customizer

        name = plugin_class.is_a?(Class) ? plugin_class.name.split('::').last : plugin_class
        raise ArgumentError,
              "#{name} must be installed at the datasource level via @agent.use(plugin, {})"
      end

      def normalize_scopes(value)
        list = Array(value).map(&:to_sym).uniq
        list = SCOPE_KEYS if list.empty?
        unknown = list - SCOPE_KEYS
        return list if unknown.empty?

        raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "Unknown scopes: #{unknown.join(", ")}. Allowed: #{SCOPE_KEYS.join(", ")}."
      end

      def resolve_ids(context, field)
        records = context.get_records([field])
        records = [records].compact unless records.is_a?(Array)
        records.filter_map { |r| r[field] || r[field.to_sym] }
      rescue StandardError => e
        ForestAdminDatasourceMambuPayments.logger.warn(
          "[forest_admin_datasource_mambu_payments] failed to resolve ids from '#{field}': " \
          "#{e.class}: #{e.message}"
        )
        []
      end

      # Per-id rescue so a single API failure doesn't abort the remaining ids.
      def each_with_rescue(ids, label)
        succeeded = []
        failed = []
        ids.each do |id|
          yield id
          succeeded << id
        rescue StandardError => e
          ForestAdminDatasourceMambuPayments.logger.warn(
            "[forest_admin_datasource_mambu_payments] #{label} failed for ##{id}: #{e.class}: #{e.message}"
          )
          failed << [id, "#{e.class}: #{e.message}"]
        end
        [succeeded, failed]
      end

      def present?(value)
        !value.nil? && value.to_s != ''
      end

      def to_int(value)
        return nil unless present?(value)

        Integer(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def write_back(context, field, value)
        return :skipped if field.nil? || value.nil?

        context.collection.update(context.filter, { field => value })
        :ok
      rescue StandardError => e
        ForestAdminDatasourceMambuPayments.logger.warn(
          "[forest_admin_datasource_mambu_payments] write-back to '#{field}' failed: #{e.class}: #{e.message}"
        )
        [:failed, "#{e.class}: #{e.message}"]
      end

      def write_back_warning(writeback)
        return nil unless writeback.is_a?(Array) && writeback.first == :failed

        " (warning: could not write the id back to the host record: #{writeback.last})"
      end
    end
  end
end
