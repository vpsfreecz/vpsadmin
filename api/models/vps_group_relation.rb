class VpsGroupRelation < ::ActiveRecord::Base
  belongs_to :vps_group
  belongs_to :other_vps_group,
    class_name: 'VpsGroup', foreign_key: :other_vps_group_id

  enum group_relation: %i(group_needs group_conflicts)
end
