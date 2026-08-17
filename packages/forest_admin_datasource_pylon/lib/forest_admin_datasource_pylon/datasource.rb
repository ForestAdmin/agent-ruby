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
    #
    # Their custom fields are introspected here, one call per object type, as
    # Pylon indexes its definitions by object type and asks for one on every
    # call. Each entry stays on the collection it belongs to: a custom field is
    # filtered through the very slug it is read by, which the collection's
    # `api_filters` already carries, so there is no datasource-wide mapping to
    # hold — and two Pylon datasources in the same agent share nothing.
    #
    # An introspection that fails costs the custom columns, not the datasource:
    # `fetch_custom_fields` degrades to an empty list and the agent boots on the
    # native schema.
    def register_collections
      custom_fields = Schema::CustomFieldsIntrospector.new(@client)

      add_collection(Collections::Issue.new(self, custom_fields: custom_fields.issue_custom_fields))
      add_collection(Collections::Account.new(self, custom_fields: custom_fields.account_custom_fields))
      add_collection(Collections::Contact.new(self, custom_fields: custom_fields.contact_custom_fields))
      # Pylon carries custom fields on issues, accounts and contacts only:
      # neither an agent nor a team has any.
      add_collection(Collections::User.new(self))
      add_collection(Collections::Team.new(self))
    end
  end
end
