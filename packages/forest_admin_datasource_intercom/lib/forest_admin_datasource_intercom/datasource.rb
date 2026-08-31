module ForestAdminDatasourceIntercom
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration

    def initialize(access_token:, **options)
      super()
      @configuration = Configuration.new(access_token: access_token, **options)
      @client = Client.new(@configuration)

      register_collections
    end

    # The datasource is what a Rails error page or a `logger.debug` is likeliest
    # to print, and it holds the client whose connections carry the access token.
    # Every collection will reach that token the same way, through the
    # `@datasource` the toolkit's Collection keeps, so cutting the chain here
    # covers them too -- and spares the recursive dump the default `inspect`
    # walks into, a datasource and its collections pointing at each other.
    def inspect
      "#<#{self.class.name} collections=#{collections.keys.inspect}>"
    end

    private

    # The reference collections first: they are what turns an assignee id into a
    # teammate and a state id into a label, and nothing else in the schema points
    # at them yet. Conversations and Tickets follow, and no request is made here
    # -- each collection reads its endpoint when it is listed, so a datasource
    # boots whatever Intercom is doing.
    def register_collections
      add_collection(Collections::Admin.new(self))
      add_collection(Collections::Team.new(self))
      add_collection(Collections::TicketType.new(self))
      add_collection(Collections::TicketState.new(self))
    end
  end
end
