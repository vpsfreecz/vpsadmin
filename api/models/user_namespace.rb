class UserNamespace < ActiveRecord::Base
  belongs_to :user
  belongs_to :user_namespace_ugid
  has_many :user_namespace_blocks
  has_many :dataset_in_pools
  has_many :nodes, through: :user_namespace_nodes

  include Lockable

  def ugid
    user_namespace_ugid.ugid
  end
end
