module NodeCtld::RemoteCommands
  class Reinit < Base
    handle :reinit

    def exec
      ret = {}
      db = nil

      @resources.each do |r|
        case r
        when 'shaper'
          log(:info, :remote, 'Reinitializing shaper')
          NodeCtld::Shaper.reinit
          ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({ output: ret })
    end
  end
end
