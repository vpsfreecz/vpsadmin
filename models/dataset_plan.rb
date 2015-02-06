class DatasetPlan < ActiveRecord::Base
  has_many :dataset_in_pool_plans
  has_many :dataset_actions

  def label
    VpsAdmin::API::DatasetPlans.plans[name.to_sym].label
  end
end
