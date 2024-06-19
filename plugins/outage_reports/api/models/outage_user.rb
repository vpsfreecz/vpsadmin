class OutageUser < ApplicationRecord
  belongs_to :outage
  belongs_to :user
end
