class MonitoredEventLog < ApplicationRecord
  belongs_to :monitored_event
  serialize :value
end
