class MonitoredEvent < ActiveRecord::Base
  has_many :monitored_event_logs
  enum state: %i(monitoring confirmed unconfirmed ignored)

  attr_accessor :monitor, :object, :responsible_user

  # TODO: optimize by fetch all monitored violations in advance
  def self.report!(monitor, obj, value, passed, user)
    attrs = {
        monitor_name: monitor.name,
        class_name: obj.class.name,
        row_id: obj.id,
        state: states[:monitoring],
    }

    ret = transaction do
      event = self.find_by(attrs)

      if event.nil?
        next if passed

        if monitor.cooldown
          # Find last confirmed event of the same type
          last = self.where(
              monitor_name: monitor.name,
              class_name: obj.class.name,
              row_id: obj.id,
              state: states[:confirmed],
          ).order('created_at DESC').take

          next if last && (last.closed_at + monitor.cooldown) >= Time.now
        end

        event = self.create!(attrs)
      end

      event.monitored_event_logs << MonitoredEventLog.new(
          passed: passed,
          value: value,
      )

      if passed
        event.update!(state: states[:unconfirmed], closed_at: Time.now)
        next
      end

      if monitor.period.nil? && monitor.check_count.nil?
        fail "Monitor #{monitor.name}: specify either period or check_count"

      elsif (monitor.period && (Time.now - event.created_at) >= monitor.period) \
        || (monitor.check_count && event.check_count >= monitor.check_count)
        event.update!(state: states[:confirmed], closed_at: Time.now)
        event.monitor = monitor
        event.object = obj
        event.responsible_user = user
        next event
      end

      nil
    end

    VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert.fire(ret) if ret
  end

  def check_count
    monitored_event_logs.count
  end

  def call_action(chain, *args)
    monitor.call_action(chain, *args)
  end
end
