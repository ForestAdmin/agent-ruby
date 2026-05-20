module ForestAdminDatasourceMambuPayments
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    attr_reader :client, :configuration

    def initialize(api_key:, base_url: nil, sandbox: false)
      super()
      @configuration = Configuration.new(api_key: api_key, base_url: base_url, sandbox: sandbox)
      @client = Client.new(@configuration)

      register_collections
    end

    private

    def register_collections
      add_collection(Collections::ConnectedAccount.new(self))
      add_collection(Collections::PaymentOrder.new(self))
      add_collection(Collections::Transaction.new(self))
      add_collection(Collections::Balance.new(self))
      add_collection(Collections::AccountHolder.new(self))
      add_collection(Collections::ExternalAccount.new(self))
      add_collection(Collections::InternalAccount.new(self))
      add_collection(Collections::IncomingPayment.new(self))
      add_collection(Collections::DirectDebitMandate.new(self))
      add_collection(Collections::ExpectedPayment.new(self))
      add_collection(Collections::Event.new(self))
      add_collection(Collections::File.new(self))
      add_collection(Collections::Return.new(self))
    end
  end
end
