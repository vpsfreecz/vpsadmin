module NodeCtld
  class Commands::Vps::Copy < Commands::Base
    handle 3040
    needs :system, :osctl

    def exec
      osctl(
        %i(ct cp),
        [@vps_id, @as_id],
        {
          pool: @as_pool_name,
          consistent: @consistent,
          network_interfaces: @network_interfaces,
        },
      )
    end

    def rollback
      osctl_pool(@as_pool_name, %i(ct del), @as_id, {force: true}, {}, valid_rcs: [1])
    end
  end
end
