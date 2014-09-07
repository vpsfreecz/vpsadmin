class Mount < ActiveRecord::Base
  belongs_to :vps
  belongs_to :dataset_in_pool
end
