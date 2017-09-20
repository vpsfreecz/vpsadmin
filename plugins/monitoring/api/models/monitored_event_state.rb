class MonitoredEventState < ActiveRecord::Base
  belongs_to :monitored_event
  enum state: MonitoredEvent.states.keys
end
