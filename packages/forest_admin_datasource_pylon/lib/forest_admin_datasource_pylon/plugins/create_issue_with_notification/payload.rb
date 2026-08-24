module ForestAdminDatasourcePylon
  module Plugins
    class CreateIssueWithNotification
      # What the filled form becomes on the wire, where FormBuilder owns what
      # the operator fills.
      module Payload
        # Only meaningful on an email delivery: Pylon reads the sending address
        # and the copies off the email app they belong to. The address is
        # mandatory there — `CreateIssueWithNotification` refuses to register an
        # email delivery without one.
        EMAIL_DESTINATION = 'email'.freeze

        module_function

        def build(values, email, opts)
          payload = {
            'title' => values['Subject'],
            'body_html' => values['Message'],
            # Pylon wants a name alongside the address when it creates the
            # contact; derive it from the local part. It is ignored when the
            # contact already exists.
            'requester_email' => email,
            'requester_name' => derive_requester_name(email)
          }
          priority = opts[:priority_override] || values['Priority']
          payload['priority'] = priority if present?(priority)

          destination = destination_for(values, opts)
          payload['destination_metadata'] = metadata(destination, opts) unless internal?(destination)
          payload
        end

        # The checkbox wins over the configured destination: it is the
        # operator's call, made on the record they are looking at.
        def destination_for(values, opts)
          truthy?(values['Send as internal note']) ? IssueEnums::INTERNAL_DESTINATION : opts[:destination]
        end

        # An internal issue travels as no metadata at all rather than as
        # `{destination: 'internal'}`: that is the form the API reference names
        # for "do not contact the requester", and the one that stays right if
        # Pylon ever adds a required companion field to a real destination.
        def internal?(destination)
          destination == IssueEnums::INTERNAL_DESTINATION
        end

        def metadata(destination, opts)
          metadata = { 'destination' => destination }
          return metadata unless destination == EMAIL_DESTINATION

          metadata['email'] = opts[:sender_email]
          metadata['email_ccs'] = Array(opts[:email_ccs]) if Array(opts[:email_ccs]).any?
          metadata['email_bccs'] = Array(opts[:email_bccs]) if Array(opts[:email_bccs]).any?
          metadata
        end

        def derive_requester_name(email)
          local = email.to_s.split('@').first.to_s
          local.empty? ? email.to_s : local
        end

        def truthy?(value)
          value == true || value.to_s.casecmp('true').zero?
        end

        def present?(value)
          !value.nil? && value.to_s != ''
        end
      end
    end
  end
end
