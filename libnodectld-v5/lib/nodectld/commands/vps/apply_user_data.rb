module NodeCtld
  class Commands::Vps::ApplyUserData < Commands::Base
    handle 2036

    def exec
      VpsUserData.for_format(@format).apply(
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
