module VpsAdmind::RemoteCommands
  class Kill < Base
    handle :kill

    def exec
      cnt = 0
      msgs = {}

      if @commands == 'all'
        cnt = VpsAdmind::Worker.kill_all

      elsif @types
        @types.each do |t|
          killed = VpsAdmind::Worker.kill_by_handle(t)

          if killed == 0
            msgs[t] = 'No command with this type'
          end

          cnt += killed
        end

      else
        @commands.each do |t|
          killed = VpsAdmind::Worker.kill_by_id(t)

          if killed == 0
            msgs[t] = 'No such command'
          end

          cnt += killed
        end
      end

      {ret: :ok, output: {killed: cnt, msgs: msgs}}
    end
  end
end
