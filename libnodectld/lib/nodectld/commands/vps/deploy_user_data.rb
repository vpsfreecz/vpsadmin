module NodeCtld
  class Commands::Vps::DeployUserData < Commands::Base
    handle 2035
    # needs :system, :osctl, :vps

    def exec
      VpsUserData.for_backend(@backend).deploy(
        @vps_id,
        @format,
        @content,
        @os_template
      )

      ok
    end

    def rollback
      ok
    end
  end
end
