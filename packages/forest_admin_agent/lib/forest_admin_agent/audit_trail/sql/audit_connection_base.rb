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

        class << self
          # `establish_connection` is class-level, so two stores pointed at different databases would silently
          # clobber each other's pool and both end up writing to whichever connected last. One audit database
          # per agent is the supported shape; a second, different one is a configuration mistake worth hearing
          # about at boot.
          #
          # Under one mutex for all stores, not one each: the check, the connect and the assignment have to be
          # one step, or two stores connecting at once both pass the check and the loser writes to the winner's
          # database.
          def connect_to(database)
            connection_mutex.synchronize do
              if @database && @database != database
                raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                      'The audit trail is already connected to another database. One agent, one audit database.'
              end
              next if @database

              establish_connection(database)
              @database = database
            end
          end

          def disconnect!
            connection_mutex.synchronize do
              @database = nil
              remove_connection
            end
          end

          def connection_mutex
            @connection_mutex ||= Mutex.new
          end
        end
      end
    end
  end
end
