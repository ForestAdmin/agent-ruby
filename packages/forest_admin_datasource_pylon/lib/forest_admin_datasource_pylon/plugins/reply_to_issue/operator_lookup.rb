module ForestAdminDatasourcePylon
  module Plugins
    class ReplyToIssue
      # The active Pylon user a reply is signed as, matched on the email of the
      # Forest user running the action. Anything short of exactly one match
      # refuses the reply rather than letting the token sign it instead.
      module OperatorLookup
        Result = Struct.new(:user, :error, keyword_init: true)

        module_function

        def call(datasource, caller)
          email = caller.respond_to?(:email) ? caller.email.to_s.strip.downcase : ''
          return Result.new(error: 'Your Forest user has no email to sign the reply with.') if email.empty?

          users   = datasource.client.fetch_users(include_deactivated: false)
          matches = users.select { |user| active?(user) && addresses(user).include?(email) }
          return Result.new(user: matches.first) if matches.size == 1

          Result.new(error: refusal(email, matches.size))
        rescue APIError => e
          Result.new(error: "Could not read the Pylon users to sign the reply in your name: #{e.message}")
        end

        def active?(user)
          user.is_a?(Hash) && user['is_deactivated'] != true
        end

        def addresses(user)
          [user['email'], *Array(user['emails'])].map { |address| address.to_s.strip.downcase }
        end

        def refusal(email, count)
          if count.zero?
            return "No active Pylon user has the email #{email}, so the reply cannot be signed in your name and " \
                   'was not sent. Use the same email in Forest and Pylon.'
          end

          "#{count} active Pylon users have the email #{email}, so the reply cannot be signed in your name and " \
            'was not sent.'
        end
      end
    end
  end
end
