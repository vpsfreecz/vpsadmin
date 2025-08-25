module NodeCtld::RemoteCommands
  class Update < Base
    handle :update

    def exec
      case @command
      when 'ssh-host-keys'
        if @vps_ids&.any?
          NodeCtld::VpsSshHostKeys.update_vps_ids(@vps_ids)
        else
          NodeCtld::VpsSshHostKeys.update_all_vps
        end

      when 'os-release'
        if @vps_ids&.any?
          NodeCtld::VpsOsRelease.update_vps_ids(@vps_ids)
        else
          NodeCtld::VpsOsRelease.update_all_vps
        end

      when 'script-hooks'
        update_script_hooks(@vps_ids)

      else
        raise NodeCtld::SystemCommandFailed.new(nil, nil, "Unknown command #{@command}")
      end

      ok
    end

    protected

    def update_script_hooks(vps_ids)
      vpses = NodeCtld::RpcClient.run(&:list_vps_status_check)
      vpses.select! { |vps| vps_ids.include?(vps['id']) } if vps_ids&.any?

      vpses.each do |vps|
        hook_installer = NodeCtld::CtHookInstaller.new(vps['pool_fs'], vps['id'])
        hooks = %w[veth-up]

        cfg = NodeCtld::VpsConfig.open(vps['pool_fs'], vps['id'])
        hooks.push('pre-start', 'post-mount') if cfg.mounts.any?

        hook_installer.install_hooks(hooks)
      end
    end
  end
end
