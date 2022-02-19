require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  # Pick node based on configurable criteria
  class Operations::Node::Pick < Operations::Base
    # @param environment [::Environment, nil]
    # @param location [::Location, nil]
    # @param vps_group [::VpsGroup, nil]
    # @param except [::Node]
    # @param hypervisor_type [:vpsadminos, :openvz]
    # @return [::Node, nil]
    def run(environment: nil, location: nil, vps_group: nil, except: nil, hypervisor_type: nil)
      if environment.nil? && location.nil?
        raise ArgumentError, 'specify at least one of location or environment'
      elsif environment && location && location.environment_id != environment.id
        raise ArgumentError, 'mismatching location and environment'
      end

      nodes =
        if location
          ::Node.pick_by_location(
            location,
            except: except,
            hypervisor_type: hypervisor_type,
          )
        else
          ::Node.pick_by_environment(
            environment,
            except: except,
            hypervisor_type: hypervisor_type,
          )
        end

      if vps_group
        Operations::Vps::PickNodeForGroup.run(vps_group, nodes)
      else
        nodes.first
      end
    end
  end
end
