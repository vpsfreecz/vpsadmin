module VpsAdmin::API::Notifications
  class Retry
    class InvalidState < StandardError; end

    class << self
      def retry!(delivery, publisher: Publisher.default)
        now = Time.now

        delivery.with_lock do
          delivery.reload
          unless delivery.failed_state?
            raise InvalidState, 'only failed deliveries can be retried'
          end

          delivery.update!(
            state: 'released',
            next_attempt_at: now,
            error_summary: nil
          )
        end

        publisher.publish_after_commit([delivery])
        delivery
      end
    end
  end
end
