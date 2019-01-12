module VpsAdmind
  class Commands::Vps::Passwd < Commands::Base
    handle 2002

    def exec
      Vps.new(@vps_id).passwd(@user, @password)
    end

    def rollback
      ok
    end
  end
end
