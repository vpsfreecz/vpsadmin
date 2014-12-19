module VpsAdmind
  class Commands::Vps::Start < Commands::Base
    handle 1001

    def exec
      @vps = Vps.new(@vps_id)
      fail 'fuckyou'
      @vps.start
    end

    def rollback
      @vps = Vps.new(@vps_id)
      @vps.stop
    end

    def post_save(db)
      @vps.update_status(db)
    end
  end
end
