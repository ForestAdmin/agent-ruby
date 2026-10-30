module ForestAdminDatasourcePylon
  module Plugins
    class ReplyToIssue
      # Every dynamic property of the form reads the same ThreadLookup state,
      # memoized on the render's context: one thread read per render, however
      # many fields depend on it.
      module FormBuilder
        FieldType = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

        TYPE_LABEL    = 'Reply type'.freeze
        CHANNEL_LABEL = 'Channel'.freeze
        TO_LABEL      = 'To'.freeze
        CC_LABEL      = 'CC'.freeze
        MESSAGE_LABEL = 'Message'.freeze

        PUBLIC_REPLY  = 'Public reply'.freeze
        INTERNAL_NOTE = 'Internal note'.freeze

        module_function

        def build(datasource, opts)
          states = ObjectSpace::WeakMap.new
          state  = ->(context) { states[context] ||= ThreadLookup.call(datasource, context, opts) }

          fields = []
          fields << type_field(state) if opts[:allow_internal_note]
          fields << channel_field(state, opts)
          fields << recipients_field(TO_LABEL, state, opts, :to)
          fields << recipients_field(CC_LABEL, state, opts, :cc)
          fields << message_field
        end

        def public_reply?(context, opts)
          !opts[:allow_internal_note] || context.get_form_value(TYPE_LABEL) == PUBLIC_REPLY
        end

        def type_field(state)
          { type: FieldType::ENUM, label: TYPE_LABEL, is_required: true,
            enum_values: ->(context) { state.call(context).target ? [PUBLIC_REPLY, INTERNAL_NOTE] : [INTERNAL_NOTE] },
            default_value: ->(context) { state.call(context).target ? PUBLIC_REPLY : INTERNAL_NOTE },
            description: 'A public reply reaches the customer; an internal note is seen by your team only.' }
        end

        def channel_field(state, opts)
          { type: FieldType::STRING, label: CHANNEL_LABEL, is_read_only: true,
            if_condition: ->(context) { public_reply?(context, opts) },
            value: ->(context) { channel_text(state.call(context), opts) },
            description: 'Pylon delivers the reply on the channel the customer used. It cannot be changed here.' }
        end

        def channel_text(state, opts)
          return state.error if state.error
          return "Reply sent via #{state.target.channel_label}" if state.target

          no_target = 'This issue has no customer-visible message, so it cannot get a public reply.'
          opts[:allow_internal_note] ? "#{no_target} Post an internal note instead." : no_target
        end

        def recipients_field(label, state, opts, side)
          { type: FieldType::STRING_LIST, label: label, is_required: side == :to,
            if_condition: lambda { |context|
              target = state.call(context).target
              public_reply?(context, opts) && !target.nil? && target.email?
            },
            default_value: ->(context) { state.call(context).target&.public_send(side) || [] },
            description: 'Pre-filled from the latest email of the conversation, support addresses left out.' }
        end

        def message_field
          { type: FieldType::STRING, label: MESSAGE_LABEL, widget: 'RichText', is_required: true }
        end
      end
    end
  end
end
