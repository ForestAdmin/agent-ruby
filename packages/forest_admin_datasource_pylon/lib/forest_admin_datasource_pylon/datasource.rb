module ForestAdminDatasourcePylon
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration

    def initialize(api_key:, **options)
      super()
      @configuration = Configuration.new(api_key: api_key, **options)
      @client = Client.new(@configuration)

      register_collections
    end

    private

    def register_collections
      add_collection(Collections::Issue.new(self))
    end
  end
end
