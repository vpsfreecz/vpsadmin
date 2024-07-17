require_relative 'base'

module VpsAdmin::Supervisor
  class Node::DnsStatus < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('dns_statuses'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'dns_statuses')

      queue.subscribe do |_delivery_info, _properties, payload|
        status = JSON.parse(payload)

        status['zones'].each do |zone|
          update_zone(zone)
        end
      end
    end

    protected

    def update_zone(zone)
      dns_server_zone = ::DnsServerZone.joins(:dns_zone, :dns_server).find_by(
        dns_zones: { name: zone['name'] },
        dns_servers: { node_id: node.id }
      )
      return if dns_server_zone.nil?

      dns_server_zone.update!(
        last_check_at: Time.at(zone['time']),
        serial: zone['serial'],
        loaded_at: Time.at(zone['loaded']),
        expires_at: zone['expires'] && Time.at(zone['expires']),
        refresh_at: zone['expires'] && Time.at(zone['refresh'])
      )
    end
  end
end
