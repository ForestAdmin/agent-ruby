module ForestAdminDatasourceRpc
  class ReconciliateRpc < ForestAdminDatasourceCustomizer::Plugins::Plugin
    def run(datasource_customizer, _collection_customizer = nil, options = {})
      datasource_customizer.composite_datasource.datasources.each do |datasource|
        real_datasource = get_datasource(datasource)
        next unless real_datasource.is_a?(ForestAdminDatasourceRpc::Datasource)

        # Disable search for non-searchable collections
        real_datasource.collections.each_value do |collection|
          unless collection.schema[:searchable]
            cz = datasource_customizer.get_collection(get_collection_name(options[:rename], collection.name))
            cz.disable_search
          end
        end

        # Add relations from rpc_relations
        (real_datasource.rpc_relations || {}).each do |collection_name, relations|
          collection_name = get_collection_name(options[:rename], collection_name)
          cz = datasource_customizer.get_collection(collection_name)

          relations.each do |relation_name, relation_definition|
            add_relation(cz, options[:rename], relation_name.to_s, relation_definition)
          end
        end
      end
    end

    private

    def get_datasource(datasource)
      # can be publication -> rename deco or a custom one
      while datasource.is_a?(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator)
        datasource = datasource.child_datasource
      end

      datasource
    end

    def get_collection_name(renames, collection_name)
      name = collection_name

      if renames.is_a?(Proc)
        name = renames.call(collection_name)
      elsif renames.is_a?(Hash) && renames.key?(collection_name.to_s)
        name = renames[collection_name.to_s]
      end

      name
    end

    def add_relation(collection_customizer, renames, relation_name, relation_definition)
      relation = relation_definition.transform_keys(&:to_sym)
      foreign_collection = get_collection_name(renames, relation[:foreign_collection])
      options = relation.except(:type, :foreign_collection, :through_collection)

      case relation[:type]
      when 'ManyToMany'
        through_collection = get_collection_name(renames, relation[:through_collection])
        collection_customizer.add_many_to_many_relation(relation_name, foreign_collection, through_collection, options)
      when 'OneToMany'
        collection_customizer.add_one_to_many_relation(relation_name, foreign_collection, options)
      when 'OneToOne'
        collection_customizer.add_one_to_one_relation(relation_name, foreign_collection, options)
      when 'ManyToOne'
        collection_customizer.add_many_to_one_relation(relation_name, foreign_collection, options)
      else
        raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "Unsupported relation type: #{relation[:type]}"
      end
    end
  end
end
