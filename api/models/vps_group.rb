class VpsGroup < ::ActiveRecord::Base
  belongs_to :user

  has_many :my_vps_group_relations,
    class_name: 'VpsGroupRelation', foreign_key: :vps_group_id,
    dependent: :delete_all

  has_many :other_vps_group_relations,
    class_name: 'VpsGroupRelation', foreign_key: :other_vps_group_id,
    dependent: :delete_all

  has_many :vpses

  enum group_type: %i(group_none group_keep_together group_keep_apart)

  validates :label, presence: true
  validate :validate_group_type

  def can_destroy?
    vpses.count == 0
  end

  # @return [ActiveRecord::Relation]
  def all_vps_group_relations
    ::VpsGroupRelation.where(
      'vps_group_id = ? OR other_vps_group_id = ?',
      id, id
    ).group('id')
  end

  # @param group_relation ['group_needs', 'group_conflicts']
  # @return [Array<::VpsGroup>]
  def all_related_vps_groups(group_relation = nil)
    ret = []

    q = all_vps_group_relations
    q = q.includes(:vps_group, :other_vps_group)
    q = q.where(group_relation: group_relation) if group_relation
    q.each do |rel|
      if rel.vps_group_id == id
        ret << rel.other_vps_group
      else
        ret << rel.vps_group
      end
    end

    ret
  end

  # @param vps [::Vps]
  # @return [ActiveModel::Errors]
  def validate_vps_add(vps)
    v = VpsAdmin::API::VpsGroupValidator.new(self)
    v.validate_vps_add(vps)
    v.errors
  end

  # @param vps [::Vps]
  # @param node [::Node] target node
  def validate_vps_migrate(vps, node)
    v = VpsAdmin::API::VpsGroupValidator.new(self)
    v.validate_vps_migrate(vps, node)
    v.errors
  end

  # @param rel [::VpsGroupRelation]
  # @return [ActiveModel::Errors]
  def validate_relation_add(rel)
    if rel.vps_group != self
      raise ArgumentError, 'invalid relation'
    end

    v = VpsAdmin::API::VpsGroupValidator.new(self)
    v.validate_relation_add(rel)
    v.errors
  end

  protected
  def validate_group_type
    return unless group_type_changed?

    v = VpsAdmin::API::VpsGroupValidator.new(self, errors: errors)
    v.validate
  end
end
