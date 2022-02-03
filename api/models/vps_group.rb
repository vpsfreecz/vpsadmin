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

  def can_destroy?
    vpses.count == 0
  end
end
