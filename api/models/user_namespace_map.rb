class UserNamespaceMap < ActiveRecord::Base
  belongs_to :user_namespace
  has_one :user_namespace_map_ugid_one,
          class_name: 'UserNamespaceMapUgid',
          foreign_key: 'user_namespace_map_id',
          dependent: :nullify
  belongs_to :user_namespace_map_ugid
  has_many :dataset_in_pools
  has_many :user_namespace_map_entries, dependent: :delete_all
  has_many :user_namespace_map_nodes
  has_many :nodes, through: :user_namespace_map_nodes

  include Lockable

  def self.create!(userns, label)
    self.transaction do
      ugid = ::UserNamespaceMapUgid.where(
        user_namespace_map_id: nil,
      ).order('ugid').take!

      map = super(
        user_namespace: userns,
        user_namespace_map_ugid: ugid,
        label: label,
      )

      ugid.update!(user_namespace_map: map)

      map
    end
  end

  def ugid
    user_namespace_map_ugid.ugid
  end

  def in_use?
    dataset_in_pools.any?
  end
end
