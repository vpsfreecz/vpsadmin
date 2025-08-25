module NodeCtld
  class Commands::Vps::DeployUserData < Commands::Base
    handle 2035

    def exec
      VpsUserData.for_format(@format).deploy(
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
