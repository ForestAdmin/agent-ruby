module ForestAdminDatasourceIntercom
  module Collections
    # An attribute whose name is already a column or relation (measured: a contact attribute named `id`) is
    # skipped with a warning, so relations must be declared first. Dates arrive as epoch seconds.
    module CustomAttributes
      private

      def register_attribute_columns
        @attribute_columns = @attributes.reject { |attribute| collides?(attribute) }
        @attribute_columns.each { |attribute| add_column(attribute.column_name, attribute.column_type) }
      end

      def attribute_columns = @attribute_columns || []

      # What the translator needs of them: the names the schema published, so a
      # filter reaching one is refused with the reason the table carries for
      # the whole family rather than with the message for a column that is not
      # in it.
      def attribute_column_names = attribute_columns.map(&:column_name)

      # What the log calls these, which is the workspace's own vocabulary: a
      # ticket attribute is declared per ticket type, a contact attribute per
      # model.
      def attribute_kind = raise(NotImplementedError, "#{self.class} did not implement attribute_kind")

      def collides?(attribute)
        return false unless fields.key?(attribute.column_name)

        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} skips the #{attribute_kind} attribute " \
          "#{attribute.name.inspect}: a native column or relation already carries the name " \
          "#{attribute.column_name.inspect}, and overwriting it would show the attribute where the operator " \
          'expects the record field. Rename it in Intercom to publish it.'
        )
        true
      end

      # Nil rather than absent when the record lacks the attribute: the column exists on every row.
      def attribute_values(values)
        held = values.is_a?(Hash) ? values : {}

        attribute_columns.to_h do |attribute|
          [attribute.column_name, coerce_attribute(held[attribute.name], attribute)]
        end
      end

      def coerce_attribute(value, attribute)
        return nil if value.nil?
        return stamp(value) if attribute.column_type == 'Date' && value.is_a?(Numeric)

        value
      end
    end
  end
end
