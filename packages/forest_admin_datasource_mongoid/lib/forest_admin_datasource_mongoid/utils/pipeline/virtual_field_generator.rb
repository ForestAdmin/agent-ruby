module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      # When using the `asModel` options, users can request/filter on the virtual _id and parentId fields
      # of children (using the generated OneToOne relation).
      #
      # As those fields are not written to mongo, they are injected here so that they can be used like
      # any other field.
      #
      # This could be also be done by preprocessing the filter, and postprocessing the records, but this
      # solution seemed simpler, at the cost of additional pipeline stages when making queries.
      #
      # Note that a projection is taken as a parameter so that only fields which are actually used are
      # injected to save resources.
      class VirtualFieldGenerator
        def self.add_virtual(_model, stack, projection)
          set = {}

          projection.each do |colon_field|
            field = colon_field.tr(':', '.')
            is_from_one_to_one = stack.last[:as_models].any? { |f| field.start_with?("#{f}.") }

            set[field] = get_path(field) if is_from_one_to_one
          end

          set.keys.empty? ? [] : [{ '$addFields' => set }]
        end

        def self.get_path(field)
          id_identifier = '._id'
          if field.end_with?(id_identifier)
            # ... dots to exclude the last character (ex: 'author.' => 'author')
            suffix = field[0...(field.length - id_identifier.length)]

            return ConditionGenerator.tag_record_if_not_exist_by_value(
              suffix,
              { '$concat' => [{ '$toString' => '$_id' }, (suffix.empty? ? '' : ".#{suffix}")] }
            )
          end

          parent_id_identifier = '.parent_id'
          if field.end_with?(parent_id_identifier)

            if field.split('.').length > 2
              # Implementing this would require us to have knowledge of the value of asModel for
              # for virtual models under the current one, which the `stack` variable does not have.

              # If the expcetion causes issues we could simply return
              # `$${field.substring(0, field.length - 9)}._id` but that would not work if the customer
              # jumped over multiple levels of nesting.

              # As this is a use case that never happens from the UI, and that can be worked around when
              # using the API, we decided to not implement it.
              raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                    'Fetching virtual parent_id deeper than 1 level is not supported.'
            end
            suffix = field[0...(field.length - parent_id_identifier.length)]

            return ConditionGenerator.tag_record_if_not_exist_by_value(suffix, '$_id')
          end

          content_identifier = '.content'
          if field.end_with?(content_identifier)
            # FIXME: we should check that this is really a leaf field because "content" can't
            # really be used as a reserved word

            return "$#{field[0...(field.length - content_identifier.length)]}"
          end

          parent = field[0..field.rindex('.')]
          parent = parent.gsub(/\.+$/, '') # Remove trailing dots

          ConditionGenerator.tag_record_if_not_exist_by_value(parent, "$#{field}")
        end
      end
    end
  end
end
