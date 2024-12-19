require 'active_record'

module ForestAdminDatasourceActiveRecord
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :models

    def initialize(
      db_config = {},
      support_polymorphic_relations: false,
      live_query_connections: nil
    )
      super()
      @models = []
      @support_polymorphic_relations = support_polymorphic_relations
      @habtm_models = {}
      @connection_drivers = {}

      @live_query_connections = if live_query_connections.is_a?(String)
                                  { live_query_connections => 'primary' }
                                elsif live_query_connections.is_a?(Hash)
                                  live_query_connections
                                else
                                  {}
                                end

      init_orm(db_config)
      generate
    end

    def execute_native_query(connection_name, query, binds)
      unless @live_query_connections[connection_name]
        raise ForestAdminAgent::Http::Exceptions::NotFoundError,
              "Native query connection '#{connection_name}' is unknown."
      end

      begin
        connection = @live_query_connections[connection_name]

        result = ActiveRecord::Base.connects_to(database: { reading: connection.to_sym }).first.connection
                                   .exec_query(query, "SQL Native Query on '#{connection_name}'", binds)

        ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(result.to_a)
      rescue StandardError => e
        raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "Error when executing SQL query: '#{e.full_message}'"
      end
    end

    def build_binding_symbol(connection_name, binds)
      if @connection_drivers[@live_query_connections[connection_name]] == 'postgresql'
        "$#{binds.size + 1}"
      else
        '?'
      end
    end

    private

    def generate
      ActiveRecord::Base.descendants.each { |model| fetch_model(model) }
      @models.each do |model|
        add_collection(
          Collection.new(self, model, support_polymorphic_relations: @support_polymorphic_relations)
        )
      end
    end

    def primary_key?(model)
      !model.primary_key.empty?
    rescue StandardError
      false
    end

    def fetch_model(model)
      if model.name.start_with?('HABTM_')
        build_habtm(model)
      else
        @models << model unless model.abstract_class? ||
                                @models.include?(model) ||
                                !model.table_exists? ||
                                !primary_key?(model)
      end
    end

    def init_orm(db_config)
      ActiveRecord::Base.establish_connection(db_config)
      current_config = ActiveRecord::Base.connection_db_config.env_name
      configurations = ActiveRecord::Base.configurations
                                         .configurations
                                         .group_by(&:env_name)
                                         .transform_values do |configs|
        configs.to_h do |config|
          [config.name, config.adapter]
        end
      end.to_h

      @connection_drivers = configurations[current_config]
    end

    def build_habtm(model)
      if @habtm_models.key?(model.table_name)
        @habtm_models[model.table_name].left_reflection = model.right_reflection
        # when the second model is added, we can push the HABTM model to the models list
        @models << make_through_model(
          model.table_name,
          [
            @habtm_models[model.table_name].left_reflection,
            @habtm_models[model.table_name].right_reflection
          ]
        )
      else
        @habtm_models[model.table_name] = model
      end
    end

    def make_through_model(table_name, associations)
      through_model = Class.new(ActiveRecord::Base) do
        class << self
          attr_accessor :name, :table_name
        end

        def self.add_association(name, options)
          belongs_to name, required: false, **options
        end
      end

      through_model.name = table_name.singularize
      through_model.table_name = table_name
      through_model.primary_key = [associations[0].foreign_key, associations[1].foreign_key]
      associations.each do |association|
        through_model.add_association(association.name, association.options)
      end

      through_model
    end
  end
end
