# This file contains code to create and configure your Forest Admin agent
# You can customize this file according to your needs

module ForestAdminRpcAgent
  class CreateRpcAgent
    def self.setup!
      datasource = ForestAdminDatasourceActiveRecord::Datasource.new(Rails.env.to_sym)

      ForestAdminRpcAgent::Agent.instance
                                .add_datasource(datasource)
                                .build
    end
  end
end
