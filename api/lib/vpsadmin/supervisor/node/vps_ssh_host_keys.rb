require_relative 'base'

module VpsAdmin::Supervisor
  class Node::VpsSshHostKeys < Node::Base
    def self.setup(channel)
      channel.prefetch(5)
    end

    def start
      exchange = channel.direct(exchange_name)

      queue = channel.queue(
        queue_name('vps_ssh_host_keys'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'vps_ssh_host_keys')

      queue.subscribe do |_delivery_info, _properties, payload|
        vps_keys = JSON.parse(payload)
        update_vps_keys(vps_keys)
      end
    end

    protected

    def update_vps_keys(vps_keys)
      t = Time.at(vps_keys['time'])
      vps = ::Vps.find_by(id: vps_keys['vps_id'], node_id: node.id)
      return if vps.nil?

      remaining_keys = vps_keys['keys'].dup

      ::VpsSshHostKey
        .where(vps:)
        .each do |host_key|
        key_update = remaining_keys.detect { |v| v['algorithm'] == host_key.algorithm }

        if key_update.nil?
          host_key.destroy!
          next
        end

        host_key.update!(
          bits: key_update['bits'],
          fingerprint: key_update['fingerprint'],
          updated_at: t
        )

        remaining_keys.delete(key_update)
      end

      remaining_keys.each do |k|
        ::VpsSshHostKey.create!(
          vps:,
          bits: k['bits'],
          algorithm: k['algorithm'],
          fingerprint: k['fingerprint'],
          created_at: t,
          updated_at: t
        )
      end
    end
  end
end
