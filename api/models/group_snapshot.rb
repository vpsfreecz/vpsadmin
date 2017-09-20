class GroupSnapshot < ActiveRecord::Base
  belongs_to :dataset_action
  belongs_to :dataset_in_pool
end
