#!/usr/bin/env ruby
Dir.chdir('/opt/vpsadmin-api')
require '/opt/vpsadmin-api/lib/vpsadmin'

module TransactionChains
  module Maintenance
    remove_const(:Custom)

    class Custom < TransactionChain
      label 'Mounts'

      def link_chain
        ::Vps.where(
            object_state: [
                ::Vps.object_states[:active],
                ::Vps.object_states[:suspended],
                ::Vps.object_states[:soft_delete],
        ]).order('vps_server ASC, vps_id ASC').each do |vps|
          use_chain(TransactionChains::Vps::Mounts, args: vps)
        end
      end
    end
  end
end

TransactionChains::Maintenance::Custom.fire
