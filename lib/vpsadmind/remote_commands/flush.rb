module VpsAdmind::RemoteCommands
  class Flush < Base
    handle :flush

    def exec
      ret = {}
      db = nil

      @resources.each do |r|
        case r
          when 'fw'
            log(:info, :remote, 'Flushing firewall')
            VpsAdmind::Firewall.mutex.synchronize do
              fw = VpsAdmind::Firewall.new
              ret[:fw] = fw.flush(db ||= VpsAdmind::Db.new)
            end

          when 'shaper'
            log(:info, :remote, 'Flushing shaper')
            sh = VpsAdmind::Shaper.new
            sh.flush
            ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({:output => ret})
    end
  end
end
