module VpsAdmind::RemoteCommands
  class Get < Base
    handle :get

    def exec
      case @resource
        when 'config'
          ok.update({:output => {:config => $CFG.get}})

        when 'queue'
          queue = []

          @daemon.workers do |workers|
            db = VpsAdmind::Db.new

            @daemon.select_commands(db, @limit).each_hash do |row|
              t_id = row['t_id'].to_i

              catch (:next) do
                workers.each do |wid, w|
                  throw :next if w.cmd.id.to_i == t_id
                end

                queue << {
                    :id => t_id,
                    :type => row['t_type'].to_i,
                    :time => row['t_time'].to_i,
                    :m_id => row['t_m_id'].to_i,
                    :vps_id => row['t_vps'].to_i,
                    :depends_on => row['t_depends_on'].to_i,
                    :fallback => row['t_fallback'],
                    :urgent => row['t_urgent'].to_i == 1,
                    :priority => row['t_priority'].to_i,
                    :params => row['t_param'],
                }
              end
            end

            db.close

          end

          ok.update({:output => {:queue => queue}})

        else
          raise VpsAdmind::CommandFailed.new(nil, nil, "Unknown resource #{@resource}")
      end
    end
  end
end
