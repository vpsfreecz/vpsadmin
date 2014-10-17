module VpsAdmind
  class Commands::Vps::Stop < Commands::Base
    def exec
      @vps = Vps.new(@vps_id)
      @vps.stop
    end

    def post_save(db)
      @vps.update_status(db)
    end
  end
end
