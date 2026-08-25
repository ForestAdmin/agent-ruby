module ForestAdminDatasourceGraphqlHasura
  module Introspection
    # name is the root field records are queried through; type_name is the
    # GraphQL OBJECT type, which relationships reference. They only differ when
    # the Hasura metadata customizes the root fields. root_fields resolves the
    # other operation roots: { aggregate:, insert:, update:, delete: }, custom
    # names applied when the metadata declares them, derived otherwise.
    Table = Struct.new(:name, :type_name, :columns, :primary_key, :relationships, :polymorphics,
                       :root_fields, keyword_init: true)

    Column = Struct.new(:name, :type, :graphql_type, :nullable, :is_primary_key, :is_array, :is_text,
                        keyword_init: true)

    # kind is :object or :array. mapping is { local_column => remote_column },
    # where a nil side stands for the primary key of that table, and the whole
    # hash is nil when the Hasura metadata was unreachable. manual tells a
    # `manual_configuration` relationship from a foreign-key-constraint one.
    Relationship = Struct.new(:name, :kind, :remote_table, :mapping, :manual, keyword_init: true)

    # targets maps the value stored in the type column to its table:
    #   { 'Transfer' => { table: 'transfers', hasura_field: 'transfer', primary_key: 'id' } }
    Polymorphic = Struct.new(:name, :foreign_key, :type_field, :targets, keyword_init: true)
  end
end
