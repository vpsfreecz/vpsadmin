module NodeCtld
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system, :osctl, :pool, :vps

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
