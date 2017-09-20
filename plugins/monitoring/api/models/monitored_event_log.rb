class MonitoredEventLog < ActiveRecord::Base
  belongs_to :monitored_event
  serialize :value
end
