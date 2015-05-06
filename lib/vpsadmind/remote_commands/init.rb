module VpsAdmind::RemoteCommands
  class Init < Base
    handle :init

    def exec
      ret = {}
      db = nil

      @resources.each do |r|
        case r
          when 'fw'
            log(:info, :remote, 'Initializing firewall')
            VpsAdmind::Firewall.mutex.synchronize do
              fw = VpsAdmind::Firewall.new
              ret[:fw] = fw.init(db ||= VpsAdmind::Db.new)
            end

          when 'shaper'
            log(:info, :remote, 'Initializing shaper')
            sh = VpsAdmind::Shaper.new
            sh.init(db ||= VpsAdmind::Db.new)
            ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({:output => ret})
    end
  end
end
