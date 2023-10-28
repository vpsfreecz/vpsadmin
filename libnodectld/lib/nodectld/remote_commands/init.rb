module NodeCtld::RemoteCommands
  class Init < Base
    handle :init

    def exec
      ret = {}
      db = nil

      @resources.each do |r|
        case r
          when 'shaper'
            log(:info, :remote, 'Initializing shaper')
            NodeCtld::Shaper.init
            ret[:shaper] = true
        end
      end

      db && db.close
      ok.update({output: ret})
    end
  end
end
