module ForestAdminDatasourceActiveRecord
  module Utils
    class ErrorHandler
      # Handle errors from ActiveRecord operations and convert them to ValidationErrors
      # @param method [Symbol] The operation type: :create, :update, or :delete
      # @return The result of the block execution
      # @raise [ForestAdminDatasourceToolkit::Exceptions::ValidationError] When a database constraint is violated
      def self.handle_errors(method)
        yield
      rescue ActiveRecord::RecordNotUnique => _e
        message = 'The query violates a unicity constraint in the database. ' \
                  'Please ensure that you are not duplicating information across records.'

        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError, message
      rescue ActiveRecord::InvalidForeignKey => _e
        message = build_foreign_key_message(method)

        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError, message
      rescue ActiveRecord::RecordInvalid => e
        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError, e.message
      rescue StandardError => e # rubocop:disable Lint/DuplicateBranch
        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError, e.message
      end

      def self.build_foreign_key_message(method)
        base_message = 'The query violates a foreign key constraint in the database. '

        case method
        when :create, :update
          "#{base_message}Please ensure that you are not linking to a relation which was deleted."
        when :delete
          "#{base_message}Please ensure that no records are linked to the one that you wish to delete."
        else
          base_message
        end
      end
    end
  end
end
