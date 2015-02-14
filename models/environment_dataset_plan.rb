class EnvironmentDatasetPlan < ActiveRecord::Base
  belongs_to :environment
  belongs_to :dataset_plan
  has_many :dataset_in_pool_plans

  def label
    dataset_plan.label
  end
end
