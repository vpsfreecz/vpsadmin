require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Vps::Migrate < Operations::Base
    # @param vps [::Vps]
    # @param opts [Hash]
    # @return [::TransactionChain]
    def run(vps, opts)
      node = opts.fetch(:node)
      chain_opts = {}

      chain_opts[:replace_ips] = opts[:replace_ip_addresses]
      chain_opts[:transfer_ips] = opts[:transfer_ip_addresses]
      chain_opts[:swap] = opts[:swap] && opts[:swap].to_sym
      chain_opts[:maintenance_window] = opts[:maintenance_window]
      chain_opts[:finish_weekday] = opts[:finish_weekday]
      chain_opts[:finish_minutes] = opts[:finish_minutes]
      chain_opts[:send_mail] = opts[:send_mail]
      chain_opts[:reason] = opts[:reason]
      chain_opts[:cleanup_data] = opts[:cleanup_data]
      chain_opts[:no_start] = opts[:no_start]
      chain_opts[:skip_start] = opts[:skip_start]

      chain, = TransactionChains::Vps::Migrate.chain_for(vps, node).fire(vps, node, chain_opts)
      chain
    end
  end
end
