module VpsAdmin::Supervisor
  class VpsSshHostKeys
    def initialize(channel)
      @channel = channel
    end

    def start
      @channel.prefetch(5)

      exchange = @channel.direct('node.vps_ssh_host_keys')
      queue = @channel.queue('node.vps_ssh_host_keys')

      queue.bind(exchange)

      queue.subscribe do |_delivery_info, _properties, payload|
        vps_keys = JSON.parse(payload)
        update_vps_keys(vps_keys)
      end
    end

    protected
    def update_vps_keys(vps_keys)
      t = Time.at(vps_keys['time'])

      ::VpsSshHostKey.where(vps_id: vps_keys['vps_id']).each do |host_key|
        key_update = vps_keys['keys'].detect { |v| v['algorithm'] == host_key.algorithm }

        if key_update.nil?
          host_key.destroy!
          next
        end

        host_key.update!(
          bits: key_update['bits'],
          fingerprint: key_update['fingerprint'],
          updated_at: t,
        )
      end
    end
  end
end
