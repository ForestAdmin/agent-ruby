module ForestAdminDatasourcePylon
  module Plugins
    class ReplyToIssue
      # The customer-visible message a public reply answers. The channel is the
      # `source` of the first such message; the reply goes to the latest message
      # on that channel, so an email answers the latest recipients rather than
      # those of the opening message.
      class ReplyTarget
        EMAIL_SOURCE = 'email'.freeze
        CHANNEL_LABELS = { 'email' => 'email', 'slack' => 'Slack' }.freeze

        attr_reader :message_id, :source, :to, :cc

        def self.resolve(messages, support_emails: [])
          visible = Array(messages).select { |message| message.is_a?(Hash) && message['is_private'] != true }
          return nil if visible.empty?

          source = visible.first['source']
          excluded = support_emails.map(&:downcase) + team_addresses(visible)
          new(visible.reverse.find { |message| message['source'] == source }, excluded)
        end

        # The addresses the team itself wrote from, read off the thread: what
        # keeps a reply out of the support inbox when `support_emails` misses one.
        def self.team_addresses(messages)
          messages.select { |message| team_authored?(message) }
                  .filter_map { |message| message.dig('email_info', 'from_email')&.to_s&.downcase }
        end

        def self.team_authored?(message)
          author = message['author']
          author.is_a?(Hash) && author['user'].is_a?(Hash)
        end

        def self.unique_addresses(addresses, excluded = [])
          addresses.map { |address| address.to_s.strip }
                   .reject { |address| address.empty? || excluded.include?(address.downcase) }
                   .uniq(&:downcase)
        end

        def initialize(message, excluded)
          @message_id = message['id']
          @source     = message['source']
          @email_info = message['email_info'].is_a?(Hash) ? message['email_info'] : {}
          @to, @cc    = recipients(message, excluded)
        end

        def email?
          @source == EMAIL_SOURCE || !@email_info['from_email'].to_s.empty? || Array(@email_info['to_emails']).any?
        end

        def channel_label
          return CHANNEL_LABELS[EMAIL_SOURCE] if email?

          CHANNEL_LABELS.fetch(@source.to_s) { @source.to_s.empty? ? 'an unnamed channel' : @source.to_s.tr('_', ' ') }
        end

        private

        # Answering a customer's email writes back to its sender; answering the
        # team's own last email writes again to whom it went.
        def recipients(message, excluded)
          sender = self.class.team_authored?(message) ? [] : [@email_info['from_email']]
          to = self.class.unique_addresses(sender + Array(@email_info['to_emails']), excluded)
          cc = self.class.unique_addresses(Array(@email_info['cc_emails']), excluded + to.map(&:downcase))
          [to, cc]
        end
      end
    end
  end
end
