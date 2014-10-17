module VpsAdmind
  class Commands::Vps::Start < Commands::Base
    def exec
      @vps = Vps.new(@vps_id)
      @vps.start
    end

    def post_save(db)
      @vps.update_status(db)
    end
  end
end
