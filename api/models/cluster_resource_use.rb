require_relative 'confirmable'

class ClusterResourceUse < ApplicationRecord
  include ActiveSupport::NumberHelper
  include Confirmable

  belongs_to :user_cluster_resource

  enum :admin_lock_type, %i[no_lock absolute not_less not_more]

  validate :check_allocation

  attr_accessor :resource_transfer, :admin_override, :attr_changes

  def self.for_obj(obj)
    where(
      class_name: obj.class.name,
      table_name: obj.class.table_name,
      row_id: obj.id
    )
  end

  def updating?
    %w[confirmed confirm_destroy].include?(confirmed.to_s)
  end

  protected

  def check_allocation
    self.attr_changes ||= { value: }

    if ::User.current && ::User.current.role == :admin
      self.admin_limit = admin_lock_type == 'no_lock' ? nil : value
      attr_changes[:admin_limit] = admin_limit
      attr_changes[:admin_lock_type] = self.class.admin_lock_types[admin_lock_type]
    end

    used = self.class.where(
      user_cluster_resource:,
      enabled: true
    ).where.not(
      confirmed: self.class.confirmed(:confirm_destroy)
    ).sum(:value)

    total = if new_record? || resource_transfer
              used + value
            else
              used - value_was + value
            end

    label = user_cluster_resource.cluster_resource.label
    min = user_cluster_resource.cluster_resource.min
    max = user_cluster_resource.cluster_resource.max

    max_use = if resource_transfer
                user_cluster_resource.value - used
              else
                (value_was || value) + (user_cluster_resource.value - used)
              end

    if !admin_override && total > user_cluster_resource.value && total > used
      msg = "you only have #{fmt_value(user_cluster_resource.value - used)} of #{label} in " \
            "#{user_cluster_resource.environment.label} left. #{capitalize_first_letter(fmt_object_name)} " \
            "can use at most #{fmt_value(max_use)} of #{label}. "

      msg << if user_reconfigurable?
               "Either reconfigure the #{fmt_class_name} or contact support if you need more resources."
             else
               'Contact support if you need more resources.'
             end

      errors.add(:value, msg)
    end

    if !admin_override && value > max
      errors.add(:value, "one #{fmt_class_name} cannot use more than #{fmt_value(max)} of #{label} resource")

    elsif !admin_override && value < min
      errors.add(:value, "one #{fmt_class_name} cannot use less than #{fmt_value(min)} of #{label} resource")
    end

    if (value % user_cluster_resource.cluster_resource.stepsize) != 0
      errors.add(
        :value,
        "#{label} is not a multiple of step size (#{fmt_value(user_cluster_resource.cluster_resource.stepsize)})"
      )
    end

    return unless admin_limit

    case admin_lock_type
    when 'absolute'
      errors.add(:value, "you must use exactly #{fmt_value(admin_limit)} of #{label}") if admin_limit != value

    when 'not_less'
      errors.add(:value, "you must use more of #{label} than #{fmt_value(admin_limit)}") if value < admin_limit

    when 'not_more'
      errors.add(:value, "you must use less of #{label} than #{fmt_value(admin_limit)}") if value > admin_limit
    end
  end

  def user_reconfigurable?
    %w[Vps DatasetInPool].include?(class_name)
  end

  def fmt_class_name
    {
      'Vps' => 'VPS',
      'DatasetInPool' => 'dataset',
      'EnvironmentUserConfig' => 'user'
    }[class_name] || class_name
  end

  def fmt_object_name
    return fmt_class_name if new_record?

    case class_name
    when 'Vps'
      "VPS #{row_id}"
    when 'DatasetInPool'
      begin
        "dataset #{::DatasetInPool.find(row_id).dataset.full_name}"
      rescue ActiveRecord::RecordNotFound
        "dataset #{row_id}"
      end
    when 'EnvironmentUserConfig'
      "user #{row_id}"
    else
      class_name
    end
  end

  def fmt_value(value)
    case user_cluster_resource.cluster_resource.name
    when 'diskspace', 'memory', 'swap'
      number_to_human_size(value * 1024 * 1024)
    else
      value
    end
  end

  def capitalize_first_letter(str)
    str[0].upcase + str[1..]
  end
end
