require 'mongo'
require 'mongoid'

module ForestAdminDatasourceMongoid
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :models

    def initialize
      super
      generate
    end

    private

    def generate
      models = ObjectSpace.each_object(Class).select do |klass|
        klass < Mongoid::Document && !klass.name.start_with?('Mongoid::')
      end

      models.each do |model|
        add_collection(Collection.new(self, model))
      end
    end
  end
end
