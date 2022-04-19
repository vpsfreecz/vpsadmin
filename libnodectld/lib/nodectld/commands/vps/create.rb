module NodeCtld
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system, :osctl, :pool, :vps

    def exec
      # FIXME: what about onboot param?

      opts = {
        user: @userns_map,
        dataset: File.join(@pool_fs, @dataset_name),
        distribution: @distribution,
        version: @version,
        arch: @arch,
        variant: @variant,
        vendor: @vendor,
      }

      opts[:skip_image] = true if @empty

      osctl(%i(ct create), @vps_id, opts)

      osctl(%i(ct set hostname), [@vps_id, @hostname]) if @hostname
      osctl(%i(ct cgparams set), [@vps_id, 'cglimit.memory.max', 64*1024])
      osctl(%i(ct cgparams set), [@vps_id, 'cglimit.all.max', 512*1024])

      # nofile was originally set by osctld automatically, it's not working
      # because of vpsadminos#28. Until it is fixed, we'll set nofile manually.
      osctl(%i(ct prlimits set), [@vps_id, 'nofile', 1024, 1024*1024])
      osctl(%i(ct prlimits set), [@vps_id, 'nproc', 128*1024, 1024*1024])
      osctl(%i(ct prlimits set), [@vps_id, 'memlock', 65536, 9223372036854775807])

      %w(veth-up).each do |hook|
        dst = hook_path(hook)

        FileUtils.cp(
          File.join(NodeCtld.root, 'templates', 'ct', 'hook', hook),
          "#{dst}.new"
        )

        File.chmod(0500, "#{dst}.new")
        File.rename("#{dst}.new", dst)
      end

      ok
    end

    def rollback
      # TODO: if only the creation fails, osctl cleans up after itself...
      #   so the destroy would fail, because the container does not exist
      call_cmd(Commands::Vps::Destroy, vps_id: @vps_id)
      ok
    end

    protected
    def hook_path(name)
      File.join(ct_hook_dir, name)
    end
  end
end
