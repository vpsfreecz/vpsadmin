class UserNamespaceNode < ActiveRecord::Base
  belongs_to :user_namespace
  belongs_to :node
end
