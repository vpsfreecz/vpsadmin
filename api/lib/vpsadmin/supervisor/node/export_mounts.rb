require_relative 'base'

module VpsAdmin::Supervisor
  class Node::ExportMounts < Node::Base
    def self.setup(channel)
      channel.prefetch(5)
    end

    def start
      exchange = channel.direct(exchange_name)

      queue = channel.queue(
        queue_name('export_mounts'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'export_mounts')

      queue.subscribe do |_delivery_info, _properties, payload|
        export_mounts = JSON.parse(payload)
        update_export_mounts(export_mounts)
      end
    end

    protected

    def update_export_mounts(export_mounts)
      t = Time.at(export_mounts['time'])

      begin
        vps = ::Vps.find(export_mounts['vps_id'])
      rescue ActiveRecord::RecordNotFound
        return
      end

      vps_mounts = vps.export_mounts.to_a

      export_mounts['mounts'].each do |mnt|
        export = ::Export
                 .joins(:host_ip_addresses)
                 .where(
                   path: mnt['server_path'],
                   host_ip_addresses: { ip_addr: mnt['server_address'] }
                 ).take
        next if export.nil?

        vps_mnt = vps_mounts.detect do |v|
          v.export_id == export.id && v.mountpoint == mnt['mountpoint']
        end

        if vps_mnt.nil?
          vps.export_mounts.create!(
            export:,
            mountpoint: mnt['mountpoint'][0..499],
            nfs_version: mnt['nfs_version'][0..9]
          )

          next
        end

        vps_mnt.update!(
          nfs_version: mnt['nfs_version'][0..9],
          updated_at: t
        )

        vps_mounts.delete(vps_mnt)
      end

      vps_mounts.each(&:destroy)
    end
  end
end
