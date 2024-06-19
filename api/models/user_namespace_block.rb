require_relative 'lockable'

class UserNamespaceBlock < ApplicationRecord
  belongs_to :user_namespace

  include Lockable
end
