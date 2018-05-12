module NodeCtld::RemoteCommands
  class Flush < Base
    handle :flush

    def exec
      ret = {}
      db = nil

      @resources.each do |r|
        case r
          when 'fw'
            log(:info, :remote, 'Flushing firewall')
            NodeCtld::Firewall.synchronize do |fw|
              ret[:fw] = fw.flush(db ||= NodeCtld::Db.new)
            end

          when 'shaper'
            log(:info, :remote, 'Flushing shaper')
            NodeCtld::Shaper.flush
            ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({output: ret})
    end
  end
end
