module VpsAdmind::RemoteCommands
  class Get < Base
    handle :get

    def exec
      case @resource
        when 'config'
          ok.update({:output => {:config => $CFG.get}})

        when 'queue'
          queue = []

          @daemon.queues do |queues|
            db = VpsAdmind::Db.new

            @daemon.select_commands(db, @limit).each_hash do |row|
              t_id = row['id'].to_i

              catch (:next) do
                throw :next if queues.has_transaction?(t_id)

                queue << {
                    :id => t_id,
                    :chain => row['transaction_chain_id'],
                    :state => row['chain_state'],
                    :type => row['handle'].to_i,
                    :time => Time.parse(row['created_at'] + ' UTC').localtime.to_i,
                    :m_id => row['user_id'].to_i,
                    :vps_id => row['vps_id'].to_i,
                    :depends_on => row['depends_on_id'].to_i,
                    :urgent => row['urgent'].to_i == 1,
                    :priority => row['priority'].to_i,
                    :params => row['input'],
                }
              end
            end

            db.close

          end

          ok.update({:output => {:queue => queue}})

        when 'ip_map'
          map = {}
          VpsAdmind::Firewall.ip_map.dump.each { |k, v| map[k] = v.to_h }

          ok.update({:output => {:ip_map => map}})

        else
          raise VpsAdmind::CommandFailed.new(nil, nil, "Unknown resource #{@resource}")
      end
    end
  end
end
