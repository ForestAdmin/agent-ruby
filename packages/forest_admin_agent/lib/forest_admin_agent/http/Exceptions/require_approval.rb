module ForestAdminAgent
  module Http
    module Exceptions
      class RequireApproval < HttpException
        attr_reader :name, :data

        def initialize(message, name = 'RequireApproval', data = [])
          @name = name
          @data = data
          super 403, 'Forbidden', message
        end
      end
    end
  end
end
