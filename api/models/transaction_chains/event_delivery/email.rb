module TransactionChains
  class EventDelivery::Email < ::TransactionChain
    label 'Event e-mail delivery'
    allow_empty
    MAX_ATTEMPTS = 5

    def link_chain(delivery)
      return unless claim_delivery(delivery)

      mail_log = nil
      mail_server = find_delivery_mail_server(delivery)
      return unless mail_server

      mail_log = render_mail(delivery)

      if mail_log.nil?
        delivery.update!(
          state: 'skipped',
          error_summary: 'e-mail template is disabled'
        )
        return
      end

      appended = false
      append(Transactions::Mail::Send, args: [mail_server, mail_log])
      appended = true
      mail_log.update!(transaction_id: @last_id)
      delivery.update!(
        state: 'queued',
        mail_log_id: mail_log.id,
        transaction_id: @last_id,
        error_summary: nil
      )
    rescue StandardError => e
      raise if defined?(appended) && appended

      mail_log.destroy! if mail_log&.persisted? && mail_log.transaction_id.blank?
      delivery.update!(
        state: 'failed',
        error_summary: "#{e.class}: #{e.message}"
      )
    end

    protected

    def find_delivery_mail_server(delivery)
      find_mail_server
    rescue ActiveRecord::RecordNotFound => e
      retry_or_fail_delivery!(delivery, e)
      nil
    end

    def claim_delivery(delivery)
      delivery.lock!
      return false unless delivery.email_action?

      unless delivery.planned_state? || (delivery.queued_state? && delivery.transaction_id.nil?)
        return false
      end

      unless delivery.notification_receiver_available?
        delivery.update!(
          state: 'canceled',
          error_summary: 'notification receiver is disabled or muted'
        )
        return false
      end

      action = delivery.notification_receiver_action
      unless action&.email_action? && action.enabled?
        delivery.update!(
          state: 'canceled',
          error_summary: 'e-mail action is not available'
        )
        return false
      end

      delivery.update!(
        state: 'queued',
        attempt_count: delivery.attempt_count + 1,
        last_attempt_at: Time.now,
        next_attempt_at: nil
      )

      true
    end

    def render_mail(delivery)
      event = delivery.event
      template_name = delivery.template_name.presence&.to_sym ||
                      VpsAdmin::API::Events.email_template_name_for(event)

      if template_name
        return ::MailTemplate.send_mail!(
          template_name,
          VpsAdmin::API::Events.email_template_options_for(event, delivery)
        )
      end

      ::MailTemplate.send_custom(
        VpsAdmin::API::Events.email_custom_options_for(event, delivery)
      )
    end

    def retry_or_fail_delivery!(delivery, error)
      attrs = {
        error_summary: "#{error.class}: #{error.message}"
      }

      if delivery.attempt_count >= MAX_ATTEMPTS
        attrs[:state] = 'failed'
      else
        attrs[:state] = 'queued'
        attrs[:next_attempt_at] = Time.now + backoff_seconds(delivery.attempt_count)
      end

      delivery.update!(attrs)
    end

    def backoff_seconds(attempt_count)
      [60 * (2**[attempt_count - 1, 0].max), 3600].min
    end
  end
end
