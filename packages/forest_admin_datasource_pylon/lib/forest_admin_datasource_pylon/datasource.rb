module ForestAdminDatasourcePylon
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration

    def initialize(api_key:, **options)
      super()
      @configuration = Configuration.new(api_key: api_key, **options)
      @client = Client.new(@configuration)

      register_collections
    end

    # The datasource is what a Rails error page or a `logger.debug` is likeliest
    # to print, and it holds the client whose connections carry the bearer
    # token. Every collection reaches that token the same way, through the
    # `@datasource` the toolkit's Collection keeps, so cutting the chain here
    # covers them too -- and spares the recursive dump the default `inspect`
    # walks into, a datasource and its collections pointing at each other.
    def inspect
      "#<#{self.class.name} collections=#{collections.keys.inspect}>"
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
    # `fetch_custom_fields` degrades and the agent boots on the native schema.
    # The first failure also stands for the object types after it, each call
    # being bounded per request rather than across the three — see
    # `CustomFieldsIntrospector`.
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
