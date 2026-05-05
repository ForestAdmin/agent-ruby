module ForestAdminDatasourceZendesk
  module Collections
    class Ticket < BaseCollection
      module SchemaDefinition
        ColumnSchema = BaseCollection::ColumnSchema
        Operators    = BaseCollection::Operators
        STRING_OPS   = BaseCollection::STRING_OPS
        NUMBER_OPS   = BaseCollection::NUMBER_OPS
        DATE_OPS     = BaseCollection::DATE_OPS

        private

        def define_schema
          add_field('id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                           is_primary_key: true, is_read_only: true, is_sortable: true))
          add_field('subject', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                is_read_only: false, is_sortable: false))
          add_field('description', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                    is_read_only: false, is_sortable: false))
          add_field('status', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                               enum_values: ENUM_STATUS, is_read_only: false, is_sortable: true))
          add_field('priority', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                 enum_values: ENUM_PRIORITY, is_read_only: false, is_sortable: true))
          add_field('ticket_type', ColumnSchema.new(column_type: 'Enum', filter_operators: STRING_OPS,
                                                    enum_values: ENUM_TYPE, is_read_only: false, is_sortable: true))
          add_field('requester_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                     is_read_only: false, is_sortable: true))
          add_field('assignee_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                    is_read_only: false, is_sortable: true))
          add_field('group_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                 is_read_only: false, is_sortable: true))
          add_field('organization_id', ColumnSchema.new(column_type: 'Number', filter_operators: NUMBER_OPS,
                                                        is_read_only: false, is_sortable: true))
          add_field('external_id', ColumnSchema.new(column_type: 'String', filter_operators: STRING_OPS,
                                                    is_read_only: false, is_sortable: false))
          add_field('requester_email', ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL],
                                                        is_read_only: true, is_sortable: false))
          add_field('tags', ColumnSchema.new(column_type: 'Json', filter_operators: [],
                                             is_read_only: false, is_sortable: false))
          add_field('url', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                            is_read_only: true, is_sortable: false))
          add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                   is_read_only: true, is_sortable: true))
          add_field('updated_at', ColumnSchema.new(column_type: 'Date', filter_operators: DATE_OPS,
                                                   is_read_only: true, is_sortable: true))

          @custom_fields.each { |cf| add_field(cf[:column_name], cf[:schema]) }
        end

        def define_relations
          add_field('requester', ManyToOneSchema.new(
                                   foreign_collection: 'ZendeskUser',
                                   foreign_key: 'requester_id',
                                   foreign_key_target: 'id'
                                 ))
          add_field('assignee', ManyToOneSchema.new(
                                  foreign_collection: 'ZendeskUser',
                                  foreign_key: 'assignee_id',
                                  foreign_key_target: 'id'
                                ))
          add_field('organization', ManyToOneSchema.new(
                                      foreign_collection: 'ZendeskOrganization',
                                      foreign_key: 'organization_id',
                                      foreign_key_target: 'id'
                                    ))
          add_field('comments', ColumnSchema.new(column_type: [Ticket::COMMENT_THREAD_SCHEMA],
                                                 filter_operators: [], is_read_only: true))
        end
      end
    end
  end
end
