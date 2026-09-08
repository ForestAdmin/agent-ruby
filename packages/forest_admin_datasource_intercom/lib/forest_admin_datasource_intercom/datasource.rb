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
    # teammate and a state id into a label. No request is made here -- each
    # collection reads its endpoint when it is listed, so a datasource boots
    # whatever Intercom is doing, and a workspace the token cannot read costs
    # rows rather than the agent.
    def register_collections
      add_collection(Collections::Admin.new(self))
      add_collection(Collections::Team.new(self))
      # The join Intercom does not expose: without it the membership of a team is
      # an array of ids on either side, since a many-to-many needs a collection
      # to travel through.
      add_collection(Collections::TeamMembership.new(self))
      add_collection(Collections::TicketType.new(self))
      add_collection(Collections::TicketState.new(self))
      # Contacts and Companies before the collections that point at them, so a
      # relation is declared next to a target the datasource already holds.
      # Each carries the custom attributes its workspace defines, read at boot:
      # they cannot be discovered from a payload, a contact carrying the values
      # of the attributes it happens to have been given.
      add_collection(Collections::Contact.new(self, attributes: model_attributes('contact')))
      add_collection(Collections::Company.new(self, attributes: model_attributes('company')))
      add_collection(Collections::Conversation.new(self))
      # The attributes a workspace defines on its ticket types, which are
      # columns of the Tickets collection and cannot be discovered from a ticket
      # payload either -- a ticket carries the values of its own type only.
      add_collection(Collections::Ticket.new(self, attributes: ticket_attributes))
    end

    # The three boot-time reads of the datasource. Each degrades to no attribute
    # column rather than to a failed boot: a token missing a permission costs
    # the columns it could not read, never the agent.
    def ticket_attributes
      Schema::TicketAttributesIntrospector.new(@client).attributes
    end

    def model_attributes(model)
      Schema::DataAttributesIntrospector.new(@client, model: model).attributes
    end
  end
end
