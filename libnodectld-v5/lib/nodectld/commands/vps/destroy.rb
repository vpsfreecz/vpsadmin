module NodeCtld
  class Commands::Vps::Destroy < Commands::Base
    handle 3002
    needs :system

    def exec
      VpsConfig.destroy(@vps_id)
      VpsStatus.remove_vps(@vps_id)
      syscmd("consolectl stop #{@vps_id}")
      ok
    end
  end
end
