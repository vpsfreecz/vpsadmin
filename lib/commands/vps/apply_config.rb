module VpsAdmind
  class Commands::Vps::ApplyConfig < Commands::Base
    handle 2008

    def exec
      Vps.new(@vps_id).applyconfig(@configs)
      ok
    end
  end
end
