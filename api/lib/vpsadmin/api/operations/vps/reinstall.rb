require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Vps::Reinstall < Operations::Base
    include Operations::Vps::UserDataUtils

    # @param attrs [Hash]
    # @param resources [Hash] might also contain other keys
    # @param opts [Hash]
    # @option opts [::OsTemplate] :os_template
    # @option opts [::VpsUserData] :vps_user_data
    # @option opts [String] :user_data_format
    # @option opts [String] :user_data_content
    # @return [::TransactionChain]
    def run(vps, opts)
      tpl = opts.fetch(:os_template)

      if !tpl.enabled?
        error!('selected os template is disabled')

      elsif tpl.hypervisor_type != vps.node.hypervisor_type
        error!(
          "incompatible template: needs #{tpl.hypervisor_type}, but VPS is " \
          "using #{vps.node.hypervisor_type}"
        )

      elsif tpl.cgroup_version != 'cgroup_any' && tpl.cgroup_version != vps.node.cgroup_version
        error!(
          "incompatible cgroup version: #{tpl.label} needs #{tpl.cgroup_version}, " \
          "but node is using #{vps.node.cgroup_version}"
        )
      end

      set_user_data(vps, opts, os_template: tpl)

      chain, = TransactionChains::Vps::Reinstall.fire(vps, tpl, opts)
      chain
    end
  end
end
