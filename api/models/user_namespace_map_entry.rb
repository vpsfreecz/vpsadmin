class UserNamespaceMapEntry < ActiveRecord::Base
  belongs_to :user_namespace_map
  enum kind: %i(uid gid)

  def to_user
    "#{ns_id}:#{host_id}:#{count}"
  end

  def to_os
    "#{ns_id}:#{user_namespace_map.user_namespace.offset + host_id}:#{count}"
  end
end
