class MonitoredEvent < ActiveRecord::Base
  has_many :monitored_event_states
  has_many :monitored_event_logs
  belongs_to :user
  enum state: %i(monitoring confirmed unconfirmed acknowledged ignored closed)
  after_update :log_state

  attr_accessor :monitor, :object

  # TODO: optimize by fetch all monitored violations in advance
  def self.report!(monitor, obj, value, passed, user)
    ret = transaction do
      event = self.find_by(
          monitor_name: monitor.name,
          class_name: obj.class.name,
          row_id: obj.id,
          state: [
              states[:monitoring],
              states[:confirmed],
              states[:acknowledged],
              states[:ignored],
          ],
      )

      if event.nil?
        next if passed

        if monitor.cooldown
          # Find last confirmed event of the same type
          last = self.where(
              monitor_name: monitor.name,
              class_name: obj.class.name,
              row_id: obj.id,
              state: states[:closed],
          ).order('created_at DESC').take

          next if last && (last.updated_at + monitor.cooldown) >= Time.now
        end

        event = self.create!(
            monitor_name: monitor.name,
            class_name: obj.class.name,
            row_id: obj.id,
            state: states[:monitoring],
            user: user,
        )

      elsif event.user != user
        event.update!(user: user)
      end

      if %w(acknowledged ignored).include?(event.state) && event.saved_until \
         && event.saved_until <= Time.now
        event.update!(state: 'confirmed', saved_until: nil)
      end

      # Skip ignored events completely, whether they're still active or not
      if event.state == 'ignored'
        event.touch
        next
      end

      # Log measured value
      event.monitored_event_logs << MonitoredEventLog.new(
          passed: passed,
          value: value,
      )

      # Close passed events
      if passed
        if event.state == 'monitoring'
          event.update!(state: states[:unconfirmed])
          next

        else
          event.update!(state: states[:closed], last_report_at: Time.now)
          event.monitor = monitor
          event.object = obj
          next event
        end
      end

      # Send alerts about confirmed events
      if monitor.period.nil? && monitor.check_count.nil?
        fail "Monitor #{monitor.name}: specify either period or check_count"

      elsif event.state == 'confirmed'
        if monitor.repeat && (event.last_report_at + monitor.repeat) <= Time.now
          event.update!(last_report_at: Time.now)
          event.monitor = monitor
          event.object = obj
          next event

        else
          event.touch
        end

      elsif event.state == 'acknowledged'
        event.touch

      elsif (monitor.period && (Time.now - event.created_at) >= monitor.period) \
        || (monitor.check_count && event.check_count >= monitor.check_count)
        event.update!(state: states[:confirmed], last_report_at: Time.now)
        event.monitor = monitor
        event.object = obj
        next event
      end

      nil
    end

    VpsAdmin::API::Plugins::Monitoring::TransactionChains::Alert.fire(ret) if ret
  end

  def ack!(save_until)
    self.state = 'acknowledged'
    self.saved_until = save_until
    self.save!
  end

  def ignore!(save_until)
    self.state = 'ignored'
    self.saved_until = save_until
    self.save!
  end

  def check_count
    monitored_event_logs.count
  end

  def call_action(chain, *args)
    monitor.call_action(state.to_sym, chain, *args)
  end

  def closed_at
    updated_at
  end

  def label
    unless monitor
      self.monitor = VpsAdmin::API::Plugins::Monitoring.monitors.detect do |v|
        v.name == monitor_name.to_sym
      end
    end

    monitor.label
  end

  def issue
    unless monitor
      self.monitor = VpsAdmin::API::Plugins::Monitoring.monitors.detect do |v|
        v.name == monitor_name.to_sym
      end
    end

    monitor.desc
  end

  protected
  def log_state
    return if monitored_event_states.last && monitored_event_states.last.state == state
    monitored_event_states << MonitoredEventState.new(
        state: state,
    )
  end
end
