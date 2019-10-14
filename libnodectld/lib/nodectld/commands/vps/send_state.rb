module NodeCtld
  class Commands::Vps::SendState < Commands::Base
    handle 3033
    needs :system, :osctl

    def exec
      osctl(
        %i(ct send state),
        @vps_id,
        {
          clone: @clone || false,
          start: @start || false,
          restart: @restart || false,
          consistent: @consistent.nil? ? true : @consistent,
        },
        {}, {}
      )
    end

    def rollback
      ok
    end
  end
end
