module ForestAdminDatasourceIntercom
  module Collections
    # The columns a workspace's own attributes become, and the two things that
    # go wrong if they are published as they come.
    #
    # **A name can land on a column the collection already carries.** Measured
    # on a real workspace: a custom contact attribute named `id`. Adding it
    # would raise on the second declaration -- the toolkit refuses a field twice
    # -- and, if it did not, the serializer would write the attribute where the
    # operator expects the record's key. It is skipped, and the log names which
    # one, since the fix is on Intercom's side.
    #
    # Relations count as taken names, which is why every collection here
    # declares them **before** registering these columns.
    #
    # **A date arrives as epoch seconds**, like every other Intercom date, and a
    # Date column that receives an integer renders as one.
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

      # The value of each published attribute, read under the name the workspace
      # gave it and written under the column name the schema publishes -- the
      # two differ whenever the first could not travel through a Forest query
      # string.
      #
      # Nil rather than absent for an attribute the record does not carry: the
      # column exists on every row, and an absent key would read as a record
      # missing it.
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
