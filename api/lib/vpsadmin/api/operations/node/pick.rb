require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  # Pick node based on configurable criteria
  class Operations::Node::Pick < Operations::Base
    # @param environment [::Environment, nil]
    # @param location [::Location, nil]
    # @param except [::Node]
    # @param hypervisor_type [:vpsadminos]
    # @param cgroup_version [nil, 'cgroup_any', 'cgroup_v1', 'cgroup_v2']
    # @param required_diskspace [Integer, nil]
    # @return [::Node, nil]
    def run(environment: nil, location: nil, except: nil, hypervisor_type: nil, cgroup_version: nil,
            required_diskspace: nil)
      if environment.nil? && location.nil?
        raise ArgumentError, 'specify at least one of location or environment'
      elsif environment && location && location.environment_id != environment.id
        raise ArgumentError, 'mismatching location and environment'
      end

      nodes =
        if location
          ::Node.pick_by_location(
            location,
            except:,
            hypervisor_type:,
            cgroup_version:
          )
        else
          ::Node.pick_by_environment(
            environment,
            except:,
            hypervisor_type:,
            cgroup_version:
          )
        end

      return nodes.first if required_diskspace.nil?

      nodes.detect do |node|
        ::Pool.pick_by_node(
          node,
          role: :hypervisor,
          required_diskspace:
        ).any?
      end
    end
  end
end
