module ForestAdminAgent
  module Http
    module Exceptions
      class RequireApproval < HttpException
        attr_reader :name, :data

        def initialize(message, name = 'RequireApproval', data = [])
          super(403, message, name)
          @data = data
        end
      end
    end
  end
end
