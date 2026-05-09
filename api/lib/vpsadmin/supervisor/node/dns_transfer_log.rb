require 'digest'
require_relative 'base'

module VpsAdmin::Supervisor
  class Node::DnsTransferLog < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('dns_transfer_logs'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'dns_transfer_logs')

      queue.subscribe do |_delivery_info, _properties, payload|
        JSON.parse(payload).fetch('events').each do |event|
          save_event(event)
        end
      end
    end

    protected

    def save_event(event)
      dns_server_zone = ::DnsServerZone.joins(:dns_zone, :dns_server).find_by(
        dns_zones: { name: event.fetch('name') },
        dns_servers: { node_id: node.id }
      )
      return if dns_server_zone.nil?

      event_at = Time.at(event.fetch('time'))
      attrs = {
        dns_server_zone:,
        event_at:,
        status: event.fetch('status'),
        reason_code: event['reason_code'],
        reason: event['reason'],
        primary_addr: event['primary_addr'],
        serial: event['serial'],
        message: event['message'],
        raw_message: event['raw_message'],
        source_cursor: event['source_cursor']
      }
      attrs[:event_key] = event['event_key'] || event_key(event)

      log = ::DnsServerZoneTransferLog.find_or_initialize_by(event_key: attrs[:event_key])
      return if log.persisted?

      log.assign_attributes(attrs)
      log.save!

      update_latest_transfer(dns_server_zone, log)
    end

    def update_latest_transfer(dns_server_zone, log)
      return if log.started?
      return if dns_server_zone.last_transfer_at && dns_server_zone.last_transfer_at > log.event_at

      dns_server_zone.update!(
        last_transfer_log: log,
        last_transfer_at: log.event_at,
        last_transfer_status: log.status,
        last_transfer_reason_code: log.failed? ? log.reason_code : nil,
        last_transfer_reason: log.failed? ? log.reason : nil,
        last_transfer_primary_addr: log.primary_addr,
        last_transfer_serial: log.serial
      )
    end

    def event_key(event)
      Digest::SHA256.hexdigest(
        [
          node.id,
          event['source_cursor'],
          event['name'],
          event['time'],
          event['status'],
          event['reason_code'],
          event['primary_addr'],
          event['serial'],
          event['message']
        ].join("\0")
      )
    end
  end
end
