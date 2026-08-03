require_relative 'lockable'

class UserNamespace < ApplicationRecord
  belongs_to :user
  has_many :user_namespace_blocks
  has_many :user_namespace_maps
  operation_event_owner via: :user

  include Lockable
end
