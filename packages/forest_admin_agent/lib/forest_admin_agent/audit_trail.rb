module ForestAdminAgent
  # The audit trail is inert unless `config.audit_trail[:database]` was set: the agent factory builds the
  # store during setup — connecting and migrating there rather than on first write — and everything (capture
  # layers and routes) resolves it from here.
  module AuditTrail
    # One operation must not materialise an unbounded number of records: a "delete all" would otherwise read
    # every matched row and, with the pending/confirm protocol, write each of them twice. Truncation is logged,
    # never silent.
    # ponytail: 500 covers any hand-made bulk edit; raise it if a real workflow needs more.
    MAX_RECORDS_PER_OPERATION = 500

    def self.log_truncation(kept, total)
      skipped = total ? total - kept : 'further'

      Facades::Container.logger.log(
        'Warn',
        "[ForestAdmin] Audit trail: #{kept} records audited, #{skipped} skipped " \
        "(cap #{MAX_RECORDS_PER_OPERATION} per operation)"
      )
    end

    def self.options
      config = Facades::Container.config_from_cache

      (config && config[:audit_trail]) || {}
    end

    def self.store
      options[:store]
    end

    # `critical: true` makes the pending insert a precondition of the write: if the audit trail cannot record
    # that an operation is about to happen, the operation is refused. Nothing was written, so there is nothing
    # to repair and no compensating write ever happens. Default false keeps today's behaviour, where a broken
    # audit database costs rows rather than writes.
    def self.critical?
      options[:critical] == true
    end

    def self.log_failure(error)
      Facades::Container.logger.log('Error', "[ForestAdmin] Audit trail unavailable, skipping: #{error.message}")
    end

    # Runs the pending insert under the configured policy: refusing the operation when critical, logging and
    # carrying on otherwise.
    def self.gate
      return yield if critical?

      begin
        yield
      rescue StandardError => e
        log_failure(e)
        nil
      end
    end
  end
end
