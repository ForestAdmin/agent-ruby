module ForestAdminDatasourceToolkit
  module Validations
    class ChartValidator
      def self.validate?(condition, result, key_names)
        if condition
          result_keys = result.keys.join(',')
          raise ForestAdminAgent::Http::Exceptions::UnprocessableError,
                "The result columns must be named '#{key_names}' instead of '#{result_keys}'"
        end

        true
      end
    end
  end
end
