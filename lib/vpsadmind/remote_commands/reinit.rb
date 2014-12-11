module VpsAdmind::RemoteCommands
  class Reinit < Base
    handle :reinit

    def exec
      ret = {}
      db = nil

      @params[:resources].each do |r|
        case r
          when 'fw'
            log(:info, :remote, 'Reinitializing firewall')
            VpsAdmind::Firewall.mutex.synchronize do
              fw = VpsAdmind::Firewall.new
              ret[:fw] = fw.reinit(db ||= Db.new)
            end

          when 'shaper'
            log(:info, :remote, 'Reinitializing shaper')
            sh = VpsAdmind::Shaper.new(0)
            sh.reinit(db ||= VpsAdmind::Db.new)
            ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({output: ret})
    end
  end
end
