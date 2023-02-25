class NodeStatus < ActiveRecord::Base
  belongs_to :node

  enum cgroup_version: %i(cgroup_invalid cgroup_v1 cgroup_v2)
end
