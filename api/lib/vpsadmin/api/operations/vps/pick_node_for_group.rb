require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  # Pick node from a list, which would be suitable for VPS group
  class Operations::Vps::PickNodeForGroup < Operations::Base
    # @param vps_group [::VpsGroup]
    # @param nodes [::Node, nil]
    def run(vps_group, nodes)
      case vps_group.group_type
      when 'group_none'
        pick_for_none(vps_group, nodes)

      when 'group_keep_together'
        pick_for_keep_together(vps_group, nodes)

      when 'group_keep_apart'
        pick_for_keep_apart(vps_group, nodes)

      else
        fail "unexpected group type #{vps_group.group_type.inspect}"
      end
    end

    protected
    # Pick node based on group relations
    def pick_for_none(vps_group, avail_nodes)
      exclude_node_ids = []

      vps_group.all_related_vps_groups('group_conflicts').each do |grp|
        exclude_node_ids.concat(get_vpses_query(grp).pluck(:node_id))
      end

      want_node_ids = []

      vps_group.all_related_vps_groups('group_needs').each do |grp|
        exclude_node_ids.concat(get_vpses_query(grp).pluck(:node_id))
      end

      avail_nodes.each do |node|
        if exclude_node_ids.include?(node.id)
          next
        elsif want_node_ids.empty? || want_node_ids.include?(node.id)
          return node
        end
      end

      nil
    end

    # Pick a node which is used by most VPSes in this group
    def pick_for_keep_together(vps_group, avail_nodes)
      # Although in practice all VPS in the group should be on the same node,
      # this rule can be broken by admins, so let's find what nodes are in use.
      used_nodes = {}

      get_vpses_query(vps_group).pluck(:node_id).each do |node_id|
        used_nodes[node_id] ||= 0
        used_nodes[node_id] += 1
      end

      # If the group is empty, look for related groups
      if used_nodes.empty?
        vps_group.all_related_vps_groups('group_needs').each do |grp|
          get_vpses_query(grp).pluck(:node_id).each do |node_id|
            used_nodes[node_id] ||= 0
            used_nodes[node_id] += 1
          end
        end
      end

      # If we didn't find any VPS, any node is usable
      if used_nodes.empty?
        return avail_nodes.first
      end

      sorted_nodes = used_nodes.sort { |a, b| b[1] <=> a[1] }

      # Now try to find a possible node
      sorted_nodes.each do |node_id, _|
        node = avail_nodes.detect { |n| n.id == node_id }
        return node if node
      end

      # We didn't find any possible node
      nil
    end

    def pick_for_keep_apart(vps_group, avail_nodes)
      used_node_ids = []

      # Nodes of VPSes in the same group
      used_node_ids.concat(get_vpses_query(vps_group).pluck(:node_id))

      # Nodes used by conflicting related groups
      vps_group.all_related_vps_groups('group_conflicts').each do |grp|
        used_node_ids.concat(get_vpses_query(grp).pluck(:node_id))
      end

      avail_nodes.each do |node|
        return node unless used_node_ids.include?(node.id)
      end

      nil
    end

    def get_vpses_query(vps_group)
      vps_group.vpses.where(object_state: [
        ::Vps.object_states[:active],
        ::Vps.object_states[:suspended],
      ])
    end
  end
end
