class UserNamespaceMapNode < ActiveRecord::Base
  belongs_to :user_namespace_map
  belongs_to :node
end
