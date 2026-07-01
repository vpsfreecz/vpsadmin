module TransactionChains
  class User::ReportFailedLogins < ::TransactionChain
    label 'Failed logins'
    allow_empty
    MAX_EVENT_ATTEMPT_GROUPS = 20
    MAX_EVENT_ATTEMPTS_PER_GROUP = 20

    # @param user_attempt_groups [Hash<User, Array<Array<UserFailedLogin>>>]
    def link_chain(user_attempt_groups)
      concerns(
        :affect,
        *user_attempt_groups.each_key.map { |u| [u.class.name, u.id] }
      )

      now = Time.now

      user_attempt_groups.each do |user, attempt_groups|
        attempt_ids = attempt_groups.map { |grp| grp.map(&:id) }
        attempts = attempt_groups.flatten

        event = route_event!(
          'user.failed_logins',
          user:,
          source: user,
          subject: 'Failed sign-in attempts',
          summary: "#{attempts.length} failed sign-in attempts for #{user.login}",
          payload: {
            attempt_count: attempts.length,
            group_count: attempt_groups.length,
            attempt_group_ids: attempt_ids.first(MAX_EVENT_ATTEMPT_GROUPS).map do |grp|
              grp.first(MAX_EVENT_ATTEMPTS_PER_GROUP)
            end,
            ip_addrs: attempts.map { |attempt| attempt.client_ip_addr || attempt.api_ip_addr }.compact.uniq.first(20),
            auth_types: attempts.map(&:auth_type).compact.uniq.first(20),
            reasons: attempts.map(&:reason).compact.uniq.first(20)
          }
        )
        ensure_delivery_handled!(event)

        ::UserFailedLogin
          .where(id: attempt_ids.flatten)
          .update_all(reported_at: now)
      end
    end

    protected

    def ensure_delivery_handled!(event)
      return if event.nil?

      deliveries = event.event_deliveries.reload.to_a
      return if deliveries.any? { |delivery| delivery_handled?(delivery) }

      failed = deliveries.find(&:failed_state?) || deliveries.first
      detail = failed&.error_summary.presence || 'no delivery was prepared'
      raise "failed-login notification was not prepared: #{detail}"
    end

    def delivery_handled?(delivery)
      return true if delivery.skipped_state? || delivery.canceled_state? || delivery.sent_state?
      return true if delivery.prepared_state? || delivery.released_state? || delivery.sending_state?

      false
    end
  end
end
