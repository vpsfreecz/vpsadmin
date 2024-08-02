require 'base64'
require 'digest'
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

      return if !dns_server_zone.primary_type? || !dns_server_zone.dns_zone.dnssec_enabled

      update_dnskeys(dns_server_zone.dns_zone, zone['dnskeys'])
    end

    def update_dnskeys(dns_zone, dnskeys)
      # Remove obsolete records
      dns_zone.dnssec_records.each do |record|
        i = dnskeys.index { |v| v['keyid'] == record.keyid }

        if i.nil?
          record.destroy!
          next
        end

        dnskeys.delete_at(i)
      end

      # Add new records
      dnskeys.each do |dnskey|
        record = dns_zone.dnssec_records.build(
          keyid: dnskey['keyid'],
          dnskey_algorithm: dnskey['algorithm'],
          dnskey_pubkey: dnskey['pubkey']
        )

        dnskey_to_ds(dnskey, record)
        record.save!
      end
    end

    def dnskey_to_ds(dnskey, record)
      data = ''

      record.dns_zone.name.split('.').each do |v|
        data << [v.length].pack('C')
        data << v
      end

      data << "\0"

      data << [
        257,                # flags
        3,                  # protocol
        dnskey['algorithm'] # algorithm
      ].pack('nCC')

      data << Base64.decode64(dnskey['pubkey'])

      record.ds_algorithm = dnskey['algorithm']
      record.ds_digest_type = 2 # sha256
      record.ds_digest = Digest::SHA256.hexdigest(data)
      record
    end
  end
end
