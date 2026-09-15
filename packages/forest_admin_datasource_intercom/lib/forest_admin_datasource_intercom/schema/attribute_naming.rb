module ForestAdminDatasourceIntercom
  module Schema
    # What the two introspectors do identically: turn the name a workspace gave
    # an attribute into a name a Forest schema can carry, and say which
    # attribute was left out when two of them land on one column.
    #
    # They differ in where the attributes come from -- `/ticket_types` per
    # ticket type, `/data_attributes` per model -- and in the data types they
    # map, which is why `COLUMN_TYPES` stays with each of them.
    module AttributeNaming
      # What a column name may not contain, and it has nothing to do with
      # Intercom: Forest lists the fields of a request in a **comma-separated**
      # query parameter, and uses a colon to name a field through a relation.
      # A workspace names its attributes in free text -- measured, one is called
      # `ID de l'objet en question (immo, facture, user)` -- and a comma in
      # there splits the projection into fields no collection has, which the
      # agent rejects as a 400 before the page is ever read.
      UNSAFE_IN_A_COLUMN_NAME = /[,:]/

      private

      # Intercom hands these back HTML-escaped -- `Ce que j&#39;ai vérifié` --
      # which is an artefact of where they were typed, not part of the name.
      def column_name_for(name)
        CGI.unescapeHTML(name).gsub(UNSAFE_IN_A_COLUMN_NAME, ' ').squeeze(' ').strip
      end

      # An unknown data type reads as a string rather than being dropped:
      # showing the value Intercom sent beats hiding a column because its type
      # is new.
      def column_type_for(definition)
        self.class::COLUMN_TYPES.fetch(definition['data_type'].to_s, self.class::DEFAULT_COLUMN_TYPE)
      end

      # Two attributes reading as one column: the second is left out rather than
      # sharing the first's entry, which would show its values under the first's
      # name -- wrong values rather than missing ones, and worse.
      #
      # `attribute_kind` is the workspace's own vocabulary for these, which is
      # what the operator has to go and rename.
      def warn_collision(name, kept, column)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] the #{attribute_kind} attribute #{name.inspect} is left out: it " \
          "reads as the column #{column.inspect}, which #{kept.inspect} already carries. Rename one of them in " \
          'Intercom to publish both.'
        )
      end

      def attribute_kind = raise(NotImplementedError, "#{self.class} did not implement attribute_kind")
    end
  end
end
