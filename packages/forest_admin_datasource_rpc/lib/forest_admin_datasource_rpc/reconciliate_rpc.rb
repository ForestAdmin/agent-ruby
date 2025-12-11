module ForestAdminDatasourceRpc
  class ReconciliateRpc < ForestAdminDatasourceCustomizer::Plugins::Plugin
    def run(datasource_customizer, _collection_customizer = nil, _options = {})
      datasource_customizer.datasources.each do |datasource|
        next unless datasource.is_a?(ForestAdminDatasourceRpc::Datasource)

        # Disable search for non-searchable collections
        datasource.collections.each do |_name, collection|
          unless collection.schema[:searchable]
            cz = datasource_customizer.get_collection(collection.name)
            cz.disable_search
          end
        end

        # Add relations from rpc_relations
        (datasource.rpc_relations || {}).each do |collection_name, relations|
          cz = datasource_customizer.get_collection(collection_name)

          relations.each do |relation_name, relation_definition|
            add_relation(cz, relation_name, relation_definition)
          end
        end
      end
    end

    private

    def add_relation(collection_customizer, relation_name, relation_definition)
      type = relation_definition[:type] || relation_definition['type']
      foreign_collection = relation_definition[:foreign_collection] || relation_definition['foreign_collection']

      case type
      when 'ManyToMany'
        through_collection = relation_definition[:through_collection] || relation_definition['through_collection']
        collection_customizer.add_many_to_many_relation(
          relation_name,
          foreign_collection,
          through_collection,
          {
            foreign_key: relation_definition[:foreign_key] || relation_definition['foreign_key'],
            foreign_key_target: relation_definition[:foreign_key_target] || relation_definition['foreign_key_target'],
            origin_key: relation_definition[:origin_key] || relation_definition['origin_key'],
            origin_key_target: relation_definition[:origin_key_target] || relation_definition['origin_key_target']
          }
        )
      when 'OneToMany'
        collection_customizer.add_one_to_many_relation(
          relation_name,
          foreign_collection,
          {
            origin_key: relation_definition[:origin_key] || relation_definition['origin_key'],
            origin_key_target: relation_definition[:origin_key_target] || relation_definition['origin_key_target']
          }
        )
      when 'OneToOne'
        collection_customizer.add_one_to_one_relation(
          relation_name,
          foreign_collection,
          {
            origin_key: relation_definition[:origin_key] || relation_definition['origin_key'],
            origin_key_target: relation_definition[:origin_key_target] || relation_definition['origin_key_target']
          }
        )
      else # ManyToOne
        collection_customizer.add_many_to_one_relation(
          relation_name,
          foreign_collection,
          {
            foreign_key: relation_definition[:foreign_key] || relation_definition['foreign_key'],
            foreign_key_target: relation_definition[:foreign_key_target] || relation_definition['foreign_key_target']
          }
        )
      end
    end
  end
end
