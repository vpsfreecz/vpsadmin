module NodeCtld::RemoteCommands
  class Reinit < Base
    handle :reinit

    def exec
      ret = {}
      db = nil

      @resources.each do |r|
        case r
          when 'fw'
            log(:info, :remote, 'Reinitializing firewall')
            NodeCtld::Firewall.synchronize do |fw|
              ret[:fw] = fw.reinit(db ||= NodeCtld::Db.new)
            end

          when 'shaper'
            log(:info, :remote, 'Reinitializing shaper')
            NodeCtld::Shaper.reinit(db ||= NodeCtld::Db.new)
            ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({output: ret})
    end
  end
end
