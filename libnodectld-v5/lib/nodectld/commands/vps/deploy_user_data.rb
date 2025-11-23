module NodeCtld
  class Commands::Vps::DeployUserData < Commands::Base
    handle 2035
    needs :libvirt, :vps

    def exec
      case @format
      when 'script'
        active_or_distconfig_mode(domain) do
          distconfig!(domain, %w[user-script-install], input: @content)
        end

      when 'cloudinit_config', 'cloudinit_script'
        active_or_distconfig_mode(domain) do
          distconfig!(domain, %w[start])
          distconfig!(domain, %w[network-setup])
          distconfig!(domain, %w[cloud-init-install], timeout: 30 * 60)
          distconfig!(domain, ['cloud-init-deploy', @format], input: @content)
        end
      end

      VpsConfig.edit(@vps_id) do |cfg|
        cfg.user_data =
          if @format.start_with?('cloudinit_')
            VpsConfig::UserData.new(format: @format, content: @content)
          end

        ConfigDrive.create(@vps_id, cfg)
      end

      ok
    end

    def rollback
      ok
    end
  end
end
