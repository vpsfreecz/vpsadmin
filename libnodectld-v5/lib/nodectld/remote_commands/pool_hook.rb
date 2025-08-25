require 'libosctl'

module NodeCtld::RemoteCommands
  class PoolHook < Base
    handle :pool_hook

    include OsCtl::Lib::Utils::Log

    def exec
      daemon = NodeCtld::Daemon.instance

      case @hook_name.to_sym
      when :pre_import
        log(:info, 'pool-hook', "Pool #{@pool} is being imported, pausing")
        daemon.node.pool_down(@pool)
        daemon.pause

      when :post_import
        log(:info, 'pool-hook', "Pool #{@pool} has been imported")
        daemon.node.pool_up(@pool)

        if daemon.node.all_pools_up?
          log(:info, 'pool-hook', 'All pools are now online, resuming')
          NodeCtld::VethMap.update_all
          daemon.resume
        end

      when :pre_export
        log(:info, 'pool-hook', "Pool #{@pool} is being exported, pausing")
        daemon.node.pool_down(@pool)
        daemon.pause
      end

      ok
    end
  end
end
