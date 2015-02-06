class DatasetInPoolPlan < ActiveRecord::Base
  belongs_to :dataset_plan
  belongs_to :dataset_in_pool
  has_many :dataset_actions
end
