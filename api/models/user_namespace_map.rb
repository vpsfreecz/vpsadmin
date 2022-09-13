require_relative 'lockable'

class UserNamespaceMap < ActiveRecord::Base
  belongs_to :user_namespace
  has_one :user_namespace_map_ugid_one,
          class_name: 'UserNamespaceMapUgid',
          foreign_key: 'user_namespace_map_id',
          dependent: :nullify
  belongs_to :user_namespace_map_ugid
  has_many :dataset_in_pools
  has_many :user_namespace_map_entries, dependent: :delete_all
  has_many :user_namespace_map_pools
  has_many :pools, through: :user_namespace_map_pools

  include Lockable

  def self.create_direct!(userns, label)
    self.transaction do
      create_chained!(userns, label)
    end
  end

  def self.create_chained!(userns, label)
    ugid = ::UserNamespaceMapUgid.where(
      user_namespace_map_id: nil,
    ).order('ugid').take!

    map = create!(
      user_namespace: userns,
      user_namespace_map_ugid: ugid,
      label: label,
    )

    ugid.update!(user_namespace_map: map)

    map
  end

  def ugid
    user_namespace_map_ugid.ugid
  end

  def in_use?
    dataset_in_pools.any?
  end
end
