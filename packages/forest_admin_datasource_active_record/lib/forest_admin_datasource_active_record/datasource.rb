require 'active_record'

module ForestAdminDatasourceActiveRecord
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    def initialize(db_config = {})
      super()
      @models = []
      init_orm(db_config)
      generate
    end

    private

    def generate
      ActiveRecord::Base.descendants.each { |model| fetch_model(model) }
      @models.each do |model|
        add_collection(Collection.new(self, model))
      end
    end

    def fetch_model(model)
      @models << model unless model.abstract_class? || @models.include?(model) || !model.table_exists?
    end

    def init_orm(db_config)
      ActiveRecord::Base.establish_connection(db_config)
    end
  end
end
