module NodeCtld
  class Commands::StorageVolume::Clone < Commands::Base
    handle 5233
    needs :system

    def exec
      conn = LibvirtClient.new

      src_pool = conn.lookup_storage_pool_by_uuid(@src['storage_pool_uuid'])
      dst_pool = conn.lookup_storage_pool_by_uuid(@dst['storage_pool_uuid'])

      src_vol = src_pool.lookup_volume_by_name("#{@src['name']}.#{@src['format']}")

      xml = ErbTemplate.render(
        'libvirt/storage_volume.xml',
        {
          name: "#{@dst['name']}.#{@dst['format']}",
          size: @dst['size'],
          format: @dst['format']
        }
      )

      dst_pool.create_volume_xml_from(xml, src_vol)

      ok
    end

    def rollback
      conn = LibvirtClient.new
      dst_pool = conn.lookup_storage_pool_by_uuid(@sdst['storage_pool_uuid'])
      dst_vol = dst_pool.lookup_volume_by_name("#{@dst['name']}.#{@dst['format']}")
      dst_vol.delete

      ok
    end
  end
end
