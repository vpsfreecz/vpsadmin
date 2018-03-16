module NodeCtld
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system, :osctl

    def exec
      # FIXME: what about onboot param?

      osctl(
        %i(ct create),
        @vps_id,
        user: @userns,
        dataset: File.join(@pool_fs, @dataset_name),
        distribution: @distribution,
        version: @version,
        arch: @arch,
        variant: @variant,
        vendor: @vendor
      )

      osctl(%i(ct set hostname), [@vps_id, @hostname])

      # TODO: configurable veth name, routed veth
      osctl(%i(ct netif new bridge), [@vps_id, 'venet0'], link: 'lxcbr0')

      ok
    end

    def rollback
      # TODO: if only the creation fails, osctl cleans up after itself...
      #   so the destroy would fail, because the container does not exist
      call_cmd(Commands::Vps::Destroy, vps_id: @vps_id)
      ok
    end
  end
end
