class Mount < ActiveRecord::Base
  belongs_to :vps
  belongs_to :dataset_in_pool
  belongs_to :snapshot_in_pool

  include Confirmable
end
