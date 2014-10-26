class Snapshot < ActiveRecord::Base
  belongs_to :dataset
  has_many :snapshot_in_pools

  include Confirmable
end
