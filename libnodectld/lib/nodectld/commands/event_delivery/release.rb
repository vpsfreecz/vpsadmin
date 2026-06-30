require 'json'
require 'time'

module NodeCtld
  class Commands::EventDelivery::Release < Commands::Base
    handle 9002

    EXCHANGE_NAME = 'vpsadmin.notifications'.freeze
    PREPARED_STATE = 0
    RELEASED_STATE = 1
    ACTION_NAMES = %w[email webhook telegram sms].freeze
    ACTIONS = {
      0 => 'email',
      1 => 'webhook',
      '0' => 'email',
      '1' => 'webhook'
    }.freeze

    def exec
      ok
    end

    def rollback
      ok
    end

    def on_save(db)
      ids = delivery_ids
      @released_deliveries = []
      return if ids.empty?

      placeholders = ids.map { '?' }.join(',')
      rows = db.prepared(
        "SELECT id, action FROM event_deliveries WHERE id IN (#{placeholders}) AND state = ?",
        *ids,
        PREPARED_STATE
      )
      rows.each do |row|
        @released_deliveries << {
          id: row.fetch('id').to_i,
          action: normalize_action(row.fetch('action'))
        }
      end
      return if @released_deliveries.empty?

      released_ids = @released_deliveries.map { |delivery| delivery.fetch(:id) }
      released_placeholders = released_ids.map { '?' }.join(',')
      now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

      db.prepared(
        "UPDATE event_deliveries
         SET state = ?, released_at = ?, next_attempt_at = ?, updated_at = ?
         WHERE id IN (#{released_placeholders}) AND state = ?",
        RELEASED_STATE,
        now,
        now,
        now,
        *released_ids,
        PREPARED_STATE
      )
    end

    def post_save
      return if @released_deliveries.nil? || @released_deliveries.empty?

      channel = NodeBunny.create_channel
      exchange = channel.direct(EXCHANGE_NAME, durable: true)
      released_at = Time.now.utc.iso8601

      @released_deliveries.each do |delivery|
        action = delivery.fetch(:action)
        next unless action

        NodeBunny.publish_wait(
          exchange,
          JSON.dump({
                      delivery_id: delivery.fetch(:id),
                      action:,
                      released_at:
                    }),
          routing_key: "delivery.#{action}",
          persistent: true
        )
      end
    rescue StandardError => e
      log(:warn, self, "Unable to notify event delivery dispatchers: #{e.class}: #{e.message}")
    ensure
      channel&.close if channel.respond_to?(:open?) && channel.open?
    end

    protected

    def delivery_ids
      Array(@delivery_ids).map(&:to_i).uniq
    end

    def normalize_action(action)
      normalized = action.to_s
      return normalized if ACTION_NAMES.include?(normalized)

      ACTIONS[normalized]
    end
  end
end
