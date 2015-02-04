class ClusterResourceUse < ActiveRecord::Base
  belongs_to :user_cluster_resource

  validate :check_allocation

  include Confirmable

  protected
  def check_allocation
    used = self.class.where(user_cluster_resource: user_cluster_resource).sum(:value)

    if self.new_record?
      total = used + self.value
    else
      total = used - self.value_was + self.value
    end

    min = user_cluster_resource.cluster_resource.min
    max = user_cluster_resource.cluster_resource.max

    if total > user_cluster_resource.value
      errors.add(
          :value,
          "cannot allocate more #{user_cluster_resource.cluster_resource.name} than is available (#{user_cluster_resource.value - used} left)"
      )
    end

    if self.value > max
      errors.add(:value, "cannot allocate more than #{max} to one object")

    elsif self.value < min
      errors.add(:value, "cannot allocate less than #{min} to one object")
    end

    if (self.value % user_cluster_resource.cluster_resource.stepsize) != 0
      errors.add(
          :value,
          "is not a multiple of step size (#{user_cluster_resource.cluster_resource.stepsize})"
      )
    end
  end
end
