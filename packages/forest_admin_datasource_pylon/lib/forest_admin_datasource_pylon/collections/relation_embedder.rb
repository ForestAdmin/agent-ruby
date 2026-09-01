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
      Projection      = BaseCollection::Projection

      private

      # `records` are the serialized records, carrying the foreign keys `project`
      # strips off the rows; `rows` are the projected rows, in the same order.
      def embed_relations(records, rows, projection)
        # Rebuilt rather than read off the argument: `list` is also called with
        # a plain array of field names, inside the agent and in the specs, and a
        # relation read from one of those would go unprojected -- which is the
        # one shape this must not have.
        sub_projections = Projection.new(Array(projection).map(&:to_s)).relations

        projected_relations(projection).group_by { |_name, relation| relation.foreign_collection }
                                       .each do |foreign, group|
          embed_foreign(foreign, group, records, rows, sub_projections)
        end
      end

      # Grouped by foreign collection, so two relations pointing at the same one
      # are answered by a single read and their ids are deduped together.
      #
      # A relation the projection asked for is written on every row, whether or
      # not it resolved: a null foreign key, and a record the operator can no
      # longer reach, both read as "no related record" rather than as a row
      # missing the field.
      #
      # The nested record is cut down to the fields the projection named, the
      # way `project` cuts the row it sits on. The foreign collection hands back
      # everything it holds -- Pylon has no join, so a related record is read
      # through its own endpoint, which takes no field list -- and nesting that
      # whole record would answer `account:name` with every column of the
      # account, the ones the caller's permissions had the agent take out of the
      # projection included.
      #
      # The primary key is added back rather than assumed: the route's
      # projection carries it, but the nested record is what the serializer
      # reads an `included` resource's id off, and a caller inside the agent may
      # well have projected without it.
      def embed_foreign(foreign_collection, relations, records, rows, sub_projections)
        ids     = foreign_ids(records, relations)
        foreign = datasource.get_collection(foreign_collection)
        indexed = ids.empty? ? {} : foreign.records_indexed_by_id(ids)
        relations.each do |name, relation|
          wanted = projected_fields(sub_projections[name], foreign)
          rows.each_with_index do |row, index|
            related = indexed[records[index][relation.foreign_key]]
            row[name] = wanted ? wanted.re_project(related) : related
          end
        end
      end

      # The fields of the relation, plus the primary key of the collection it
      # points at. The key is unioned in by hand rather than through
      # `Projection#with_pks`, which also walks the relations of the projection
      # it is given and dereferences their schema without a nil guard: a
      # projection reaching through a relation this collection does not declare
      # would raise there, where it used to be ignored. Only the immediate
      # foreign key is wanted here, so only that is added.
      def projected_fields(sub_projection, foreign)
        return nil if sub_projection.nil?

        Projection.new(sub_projection | ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(foreign))
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
