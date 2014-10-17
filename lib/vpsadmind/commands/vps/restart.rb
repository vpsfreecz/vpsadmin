module VpsAdmind
  class Commands::Vps::Restart < Commands::Base
    handle 1003

    def exec
      @vps = Vps.new(@vps_id)
      @vps.restart
    end

    def post_save(db)
      @vps.update_status(db)
    end
  end
end
