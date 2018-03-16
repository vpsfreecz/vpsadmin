module NodeCtld
  class Commands::Vps::Start < Commands::Base
    handle 1001

    def exec
      @vps = Vps.new(@vps_id)
      @vps.start
    end

    def rollback
      @vps = Vps.new(@vps_id)
      @vps.stop
    end

    def post_save(db)
      # TODO
      # VpsStatus.new([@vps_id]).update
    end
  end
end
