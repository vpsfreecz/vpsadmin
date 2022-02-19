module VpsAdmin::API
  class VpsGroupValidator
    # @return [::VpsGroup]
    attr_reader :vps_group

    # @return [ActiveModel::Errors]
    attr_reader :errors

    # @param vps_group [::VpsGroup]
    # @param errors [ActiveModel::Errors, nil]
    def initialize(vps_group, errors: nil)
      @vps_group = vps_group
      @errors = errors || ActiveModel::Errors.new(vps_group)
    end

    # Validate group constraints
    def validate
      @self_vpses = get_self_vpses
      @self_relations = vps_group.all_vps_group_relations.to_a
      @ignore_other_vpses = []
      @patch_vpses = nil

      validate_by_type
    end

    # Validate group constraints when a VPS is added
    # @param vps [::Vps]
    def validate_vps_add(vps)
      @self_vpses = get_self_vpses + [vps]
      @self_relations = vps_group.all_vps_group_relations.to_a
      @ignore_other_vpses = [vps]
      @patch_vpses = nil

      validate_by_type
    end

    # Validate group constraints when migrating a VPS
    # @param vps [::Vps]
    # @param node [::Node]
    def validate_vps_migrate(vps, node)
      @self_vpses = get_self_vpses
      @self_relations = vps_group.all_vps_group_relations.to_a
      @ignore_other_vpses = []
      @patch_vpses = ->(vps2) do
        vps2.node = node if vps2.id == vps.id
        vps2
      end

      validate_by_type
    end

    # Validate group constraints when creating a new relation
    # @param rel [::VpsGroupRelation]
    def validate_relation_add(rel)
      @self_vpses = get_self_vpses
      @self_relations = vps_group.all_vps_group_relations.to_a + [rel]
      @ignore_other_vpses = []
      @patch_vpses = nil

      validate_by_type
    end

    protected
    attr_reader :self_vpses, :self_relations, :ignore_other_vpses, :patch_vpses

    def validate_by_type
      begin
        m = method(:"validate_#{vps_group.group_type}")
      rescue NameError
        errors.add(:group_type, "Invalid group type '#{vps_group.group_type}'")
      else
        m.call
      end
    end

    def validate_group_none
      validate_group_relations
    end

    def validate_group_keep_together
      # Check VPSes
      nodes = {}

      self_vpses.each do |vps|
        nodes[vps.node] ||= []
        nodes[vps.node] << vps
      end

      if nodes.length > 1
        errors.add(:group_type, "All VPS must be on the same node")

        nodes.map do |node, node_vpses|
          node_vpses.each do |vps|
            errors.add(:group_type, "VPS #{vps.id} is on #{node.domain_name}")
          end
        end
      end

      # Check group relations
      validate_group_relations
    end

    def validate_group_keep_apart
      # Check VPSes
      self_vpses.each do |vps1|
        self_vpses.each do |vps2|
          next if vps1 == vps2
          next if vps1.node_id != vps2.node_id

          errors.add(
            :group_type,
            "VPS #{vps1.id} and VPS #{vps2.id} are both on #{vps1.node.domain_name}"
          )
        end
      end

      # Check group relations
      validate_group_relations
    end

    def validate_group_relations
      my_node_ids = self_vpses.map(&:node_id).uniq

      # Iterate over all groups and validate the relation
      self_relations.each do |rel|
        other_grp = rel.get_other_vps_group(vps_group)

        case rel.group_relation
        when 'group_needs'
          # Check that we are on the same node
          other_vpses = get_other_vpses(other_grp)

          self_vpses.each do |my_vps|
            other_vpses.each do |other_vps|
              next if my_vps == other_vps
              next if my_vps.node_id == other_vps.node_id

              errors.add(
                :group_type,
                "Unsatisfied 'need' relation with group #{other_grp.label}: " +
                "VPS #{my_vps.id} (#{vps_group.label}) is on #{my_vps.node.domain_name}, " +
                "while VPS #{other_vps.id} (#{other_grp.label}) is on " +
                "#{other_vps.node.domain_name}"
              )
            end
          end

        when 'group_conflicts'
          # Check that no VPS is on the same node with any VPS in this group
          other_vpses = get_other_vpses(other_grp)

          self_vpses.each do |my_vps|
            other_vpses.each do |other_vps|
              next if my_vps == other_vps
              next if my_vps.node_id != other_vps.node_id

              errors.add(
                :group_type,
                "Unsatisfied 'conflict' relation with group #{other_grp.label}: " +
                "VPS #{my_vps.id} (#{vps_group.label}) is on #{my_vps.node.domain_name} " +
                "with VPS #{other_vps.id} (#{other_grp.label})"
              )
            end
          end
        end
      end
    end

    def get_self_vpses
      ret = get_vpses_query(vps_group).to_a
      ret.map!(&patch_vpses) if patch_vpses
      ret
    end

    def get_other_vpses(other_vps_group)
      ret = get_vpses_query(other_vps_group).to_a

      if ignore_other_vpses.any?
        ret.delete_if do |vps|
          ignore_other_vpses.detect { |v| v.id == vps.id }
        end
      end

      ret.map!(&patch_vpses) if patch_vpses
      ret
    end

    def get_vpses_query(for_vps_group)
      for_vps_group.vpses.where(object_state: [
        ::Vps.object_states[:active],
        ::Vps.object_states[:suspended],
      ])
    end
  end
end
