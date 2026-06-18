require 'active_record'

module ForestAdminAuditTrail
  module Sql
    # Dedicated abstract base so the audit storage keeps its own connection pool, isolated from the
    # host application's ActiveRecord::Base connection.
    class AuditConnectionBase < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
