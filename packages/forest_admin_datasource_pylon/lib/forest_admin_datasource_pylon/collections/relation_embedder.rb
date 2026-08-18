module ForestAdminDatasourcePylon
  module Collections
    # Forest asks for a ManyToOne relation as `relation:field` entries in the
    # projection and expects the related record nested under the relation name on
    # every row. Pylon has no join and no include parameter, so the records are
    # read from the foreign collection — in bulk, from the foreign keys the
    # serialized records already carry, never one request per row.
    #
    # What to embed comes from the schema rather than from a list kept here: a
    # collection embeds whatever ManyToOne relations it declares, and a relation
    # the projection does not ask for costs no request at all.
    module RelationEmbedder
      ManyToOneSchema = BaseCollection::ManyToOneSchema

      private

      # `records` are the serialized records, carrying the foreign keys `project`
      # strips off the rows; `rows` are the projected rows, in the same order.
      def embed_relations(records, rows, projection)
        projected_relations(projection).group_by { |_name, relation| relation.foreign_collection }
                                       .each { |foreign, group| embed_foreign(foreign, group, records, rows) }
      end

      # Grouped by foreign collection, so two relations pointing at the same one
      # are answered by a single read and their ids are deduped together.
      #
      # A relation the projection asked for is written on every row, whether or
      # not it resolved: a null foreign key, and a record the operator can no
      # longer reach, both read as "no related record" rather than as a row
      # missing the field.
      def embed_foreign(foreign_collection, relations, records, rows)
        ids = foreign_ids(records, relations)
        foreign = ids.empty? ? {} : datasource.get_collection(foreign_collection).records_indexed_by_id(ids)
        relations.each do |name, relation|
          rows.each_with_index { |row, index| row[name] = foreign[records[index][relation.foreign_key]] }
        end
      end

      # A foreign key Pylon left empty asks for nothing — a blank one no more
      # than a null one, and it would reach the `in` filter of the read below,
      # which refuses a blank inside a list and would fail the whole page over
      # one malformed key. The same id is asked for once however many rows point
      # at it.
      def foreign_ids(records, relations)
        keys = relations.map { |_name, relation| relation.foreign_key }
        records.flat_map { |record| keys.map { |key| record[key] } }
               .reject { |id| id.nil? || id.to_s.empty? }
               .uniq
      end

      # `account:name` asks for the `account` relation; a projected column, and a
      # relation that is not a ManyToOne, name no field to embed.
      def projected_relations(projection)
        Array(projection).map { |field| field.to_s.split(':').first }.uniq.filter_map do |name|
          relation = schema[:fields][name]
          [name, relation] if relation.is_a?(ManyToOneSchema)
        end
      end
    end
  end
end
