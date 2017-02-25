class OutageHandler < ActiveRecord::Base
  belongs_to :outage
  belongs_to :user
end
