class UserNamespace < ActiveRecord::Base
  belongs_to :user
  has_many :user_namespace_blocks
  has_many :user_namespace_maps

  include Lockable
end
