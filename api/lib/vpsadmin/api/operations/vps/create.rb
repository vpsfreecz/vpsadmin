require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Vps::Create < Operations::Base
    # @param attrs [Hash]
    # @param resources [Hash] might also contain other keys
    # @param opts [Hash]
    # @option opts [Integer] :ipv4
    # @option opts [Integer] :ipv6
    # @option opts [Integer] :ipv4_private
    # @option opts [::Location, nil] :address_location
    # @option opts [Boolean] :start
    # @return [Array(::TransactionChain, ::Vps)]
    def run(attrs, resources, opts)
      vps = ::Vps.new(attrs)
      vps.manage_hostname = vps.os_template.manage_hostname
      vps.set_cluster_resources(resources)

      raise ActiveRecord::RecordInvalid, vps unless vps.valid?

      TransactionChains::Vps::Create.fire(vps, opts)
    end
  end
end
