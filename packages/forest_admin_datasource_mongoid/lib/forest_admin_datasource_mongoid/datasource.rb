require 'mongo'
require 'mongoid'

module ForestAdminDatasourceMongoid
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :models

    def initialize
      super
      generate
    end

    def simulate_habtm(model)
      model.reflect_on_all_associations(:has_and_belongs_to_many).each do |association|
        make_through_model(model, association) unless collections.key?(create_through_model_name(model, association))
      end
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

    def make_through_model(model, association)
      # make a fake model to represent the through model
      Class.new do
        include Mongoid::Document
        class << self
          attr_accessor :name, :collection_name, :primary_key
        end

        def self.add_association(name, options)
          belongs_to name, required: false, **options
        end
      end

      options = {}
      options[:name] = create_through_model_name(model, association)
      options[:collection_name] = options[:name].downcase

      options[:associations] = [
        {
          name: model.name.demodulize.underscore.to_sym,
          foreign_collection: model.name.gsub('::', '__'),
          foreign_key: fetch_foreign_key(model),
          foreign_key_target: fetch_primary_key(association.klass)
        },
        {
          name: association.klass.name.demodulize.underscore.to_sym,
          foreign_collection: association.klass.name.gsub('::', '__'),
          foreign_key: fetch_foreign_key(association.klass),
          foreign_key_target: fetch_primary_key(model)
        }
      ]

      add_collection(ThroughCollection.new(self, options))
    end

    def create_through_model_name(model, association)
      [model, association.klass]
        .map { |klass| klass.name.split('::').last }
        .sort
        .join('_')
    end

    def fetch_primary_key(klass)
      klass.fields.find { |_, field| field.options[:identity] || field.name == '_id' }&.first
    end

    def fetch_foreign_key(klass)
      klass.fields.find { |_, field| field.options[:identity] }&.first || '_id'
      # fetch_primary_key(klass).to_s
    end
  end
end
