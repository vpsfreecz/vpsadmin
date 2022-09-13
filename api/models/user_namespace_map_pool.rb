class UserNamespaceMapPool < ActiveRecord::Base
  belongs_to :user_namespace_map
  belongs_to :pool
end
