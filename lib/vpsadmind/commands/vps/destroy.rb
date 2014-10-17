module VpsAdmind
  class Commands::Vps::Destroy < Commands::Base
    handle 3002

    def exec
      Vps.new(@vps_id).destroy
      ok
    end
  end
end
