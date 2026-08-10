begin
  require 'active_record'
rescue LoadError
  raise LoadError, 'config.audit_trail needs the activerecord gem: add `gem "activerecord"` to your Gemfile.'
end

module ForestAdminAgent
  module AuditTrail
    module Sql
      # Dedicated abstract base so the audit storage keeps its own connection pool, isolated from the
      # host application's ActiveRecord::Base connection. Also the level the `attribute` overrides in
      # AuditLog need: declaring them straight on an ActiveRecord::Base child resolves the type
      # eagerly and blows up before any connection is established.
      class AuditConnectionBase < ActiveRecord::Base
        self.abstract_class = true
      end
    end
  end
end
