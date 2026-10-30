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
          new(visible.reverse.find { |message| message['source'] == source }, support_emails)
        end

        def initialize(message, support_emails)
          @message_id = message['id']
          @source     = message['source']
          @email_info = message['email_info'].is_a?(Hash) ? message['email_info'] : {}
          @to, @cc    = recipients(support_emails.map(&:downcase))
        end

        def email?
          @source == EMAIL_SOURCE || !@email_info['from_email'].to_s.empty? || Array(@email_info['to_emails']).any?
        end

        def channel_label
          return CHANNEL_LABELS[EMAIL_SOURCE] if email?

          CHANNEL_LABELS.fetch(@source.to_s) { @source.to_s.empty? ? 'an unnamed channel' : @source.to_s.tr('_', ' ') }
        end

        private

        # The sender joins To: answering a customer's email means writing back to
        # them. The support addresses drop out, being the side that replies.
        def recipients(support)
          to = unique_addresses([@email_info['from_email'], *Array(@email_info['to_emails'])], support)
          cc = unique_addresses(Array(@email_info['cc_emails']), support + to.map(&:downcase))
          [to, cc]
        end

        def unique_addresses(addresses, excluded)
          addresses.map { |address| address.to_s.strip }
                   .reject { |address| address.empty? || excluded.include?(address.downcase) }
                   .uniq(&:downcase)
        end
      end
    end
  end
end
