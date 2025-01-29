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
        klass < Mongoid::Document && klass.name && !klass.name.start_with?('Mongoid::') && !embedded_in_relation?(klass)
      end

      models.each do |model|
        add_collection(Collection.new(self, model))
      end
    end

    def embedded_in_relation?(klass)
      klass.relations.any? { |_name, association| association.is_a?(Mongoid::Association::Embedded::EmbeddedIn) }
    end

    def fetch_primary_key(klass)
      primary_key = klass.fields.find { |_, field| field.options[:identity] || field.name == '_id' }&.first
      unless primary_key
        raise(ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "Primary key not found for #{klass.name}")
      end

      primary_key
    end
  end
end
