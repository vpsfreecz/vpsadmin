class VpsGroupRelation < ::ActiveRecord::Base
  belongs_to :vps_group
  belongs_to :other_vps_group,
    class_name: 'VpsGroup', foreign_key: :other_vps_group_id

  enum group_relation: %i(group_needs group_conflicts)

  before_validation :ensure_relation_order

  validate :validate_relation

  # @return [::VpsGroup]
  def get_other_vps_group(self_group)
    if !self_group.is_a?(::VpsGroup)
      raise ArgumentError, 'expected VpsGroup instance'
    end

    if vps_group == self_group
      other_vps_group
    else
      self_group
    end
  end

  protected
  def ensure_relation_order
    # By always settings vps_group_id as lower than other_vps_group_id,
    # we make sure that the unique constraint cannot be broken.
    if vps_group_id > other_vps_group_id
      tmp = vps_group_id
      self.vps_group_id = other_vps_group_id
      self.other_vps_group_id = tmp
    end
  end

  def validate_relation
    if vps_group == other_vps_group
      errors.add(:other_vps_group, 'must be different from vps_group')
    end

    return unless new_record?

    group_errors = vps_group.validate_relation_add(self)
    errors.merge!(group_errors)
  end
end
