module VpsAdmind
  class Commands::Vps::Stop < Commands::Base
    handle 1002

    def exec
      @vps = Vps.new(@vps_id)
      @vps.stop
    end

    def rollback
      @vps = Vps.new(@vps_id)
      @vps.start
    end

    def post_save(db)
      @vps.update_status(db)
    end
  end
end
