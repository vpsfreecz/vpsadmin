require_relative 'confirmable'

class ClusterResourceUse < ActiveRecord::Base
  include Confirmable

  belongs_to :user_cluster_resource

  enum admin_lock_type: %i(no_lock absolute not_less not_more)

  validate :check_allocation

  attr_accessor :resource_transfer, :admin_override, :attr_changes

  def self.for_obj(obj)
    self.where(
      class_name: obj.class.name,
      table_name: obj.class.table_name,
      row_id: obj.id
    )
  end

  def updating?
    %w(confirmed confirm_destroy).include?(confirmed.to_s)
  end

  protected
  def check_allocation
    self.attr_changes ||= {value: self.value}

    if ::User.current && ::User.current.role == :admin
      self.admin_limit = admin_lock_type == 'no_lock' ? nil : self.value
      attr_changes[:admin_limit] = self.admin_limit
      attr_changes[:admin_lock_type] = self.class.admin_lock_types[self.admin_lock_type]
    end

    used = self.class.where(
      user_cluster_resource: user_cluster_resource,
      enabled: true
    ).where.not(
      confirmed: self.class.confirmed(:confirm_destroy)
    ).sum(:value)

    if self.new_record? || resource_transfer
      total = used + self.value
    else
      total = used - self.value_was + self.value
    end

    min = user_cluster_resource.cluster_resource.min
    max = user_cluster_resource.cluster_resource.max

    if !admin_override && total > user_cluster_resource.value && total > used
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

    if self.admin_limit
      case self.admin_lock_type
      when 'absolute'
        errors.add(:value, "cannot allocate other than #{admin_limit}") if admin_limit != value

      when 'not_less'
        errors.add(:value, "cannot allocate less than #{admin_limit}") if value < admin_limit

      when 'not_more'
        errors.add(:value, "cannot allocate more than #{admin_limit}") if value > admin_limit
      else

      end
    end
  end
end
