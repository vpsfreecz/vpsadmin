class DatasetPlan < ApplicationRecord
  has_many :environment_dataset_plans
  has_many :dataset_actions

  def label
    VpsAdmin::API::DatasetPlans.plans[name.to_sym].label
  end

  def description
    VpsAdmin::API::DatasetPlans.plans[name.to_sym].desc
  end
end
