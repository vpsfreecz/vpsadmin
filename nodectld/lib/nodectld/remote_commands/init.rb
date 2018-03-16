module NodeCtld::RemoteCommands
  class Init < Base
    handle :init

    def exec
      ret = {}
      db = nil

      @resources.each do |r|
        case r
          when 'fw'
            log(:info, :remote, 'Initializing firewall')
            NodeCtld::Firewall.synchronize do |fw|
              ret[:fw] = fw.init(db ||= NodeCtld::Db.new)
            end

          when 'shaper'
            log(:info, :remote, 'Initializing shaper')
            sh = NodeCtld::Shaper.new
            sh.init(db ||= NodeCtld::Db.new)
            ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({:output => ret})
    end
  end
end
