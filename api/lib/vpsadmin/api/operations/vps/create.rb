require 'vpsadmin/api/operations/base'
require_relative 'user_data_utils'

module VpsAdmin::API
  class Operations::Vps::Create < Operations::Base
    include Operations::Vps::UserDataUtils

    # @param attrs [Hash]
    # @param resources [Hash] might also contain other keys
    # @param opts [Hash]
    # @option opts [Integer] :ipv4
    # @option opts [Integer] :ipv6
    # @option opts [Integer] :ipv4_private
    # @option opts [::Location, nil] :address_location
    # @option opts [Boolean] :start
    # @option opts [::VpsUserData] :vps_user_data
    # @option opts [String] :user_data_format
    # @option opts [String] :user_data_content
    # @return [Array(::TransactionChain, ::Vps)]
    def run(attrs, resources, opts)
      vps = ::Vps.new(attrs)
      vps.vm_type =
        case vps.node.hypervisor_type
        when 'vpsadminos'
          'container'
        when 'libvirt'
          'qemu_managed'
        else
          raise "Unsupported hypervisor type #{vps.node.hypervisor_type.inspect}"
        end
      vps.manage_hostname = vps.os_template.manage_hostname
      vps.os_family = vps.os_template.os_family
      vps.set_cluster_resources(resources)

      raise ActiveRecord::RecordInvalid, vps unless vps.valid?

      set_user_data(vps, opts)

      TransactionChains::Vps::Create.fire(vps, opts)
    end
  end
end
