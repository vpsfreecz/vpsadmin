class UserNamespaceBlock < ActiveRecord::Base
  belongs_to :user_namespace

  include Lockable
end
