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

    # The five collections are registered together: each one declares relations
    # pointing at the others, and a relation whose foreign collection is missing
    # is a schema the agent refuses to boot on.
    def register_collections
      add_collection(Collections::Issue.new(self))
      add_collection(Collections::Account.new(self))
      add_collection(Collections::Contact.new(self))
      add_collection(Collections::User.new(self))
      add_collection(Collections::Team.new(self))
    end
  end
end
