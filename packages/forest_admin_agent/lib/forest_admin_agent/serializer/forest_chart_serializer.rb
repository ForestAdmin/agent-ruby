require 'securerandom'

module ForestAdminAgent
  module Serializer
    class ForestChartSerializer
      def self.serialize(chart)
        {
          data: {
            id: SecureRandom.uuid,
            type: 'stats',
            attributes: {
              value: chart
            }
          }
        }
      end
    end
  end
end
