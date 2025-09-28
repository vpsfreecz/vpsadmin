module NodeCtld
  class Commands::StorageVolume::Create < Commands::Base
    handle 5230
    needs :system

    def exec
      conn = LibvirtClient.new
      pool = conn.lookup_storage_pool_by_uuid(@storage_pool_uuid)

      xml = ErbTemplate.render(
        'libvirt/storage_volume.xml',
        {
          name: "#{@name}.#{@format}",
          size: @size,
          format: @format
        }
      )

      pool.create_volume_xml(xml)

      ok
    end

    def rollback
      conn = LibvirtClient.new
      pool = conn.lookup_storage_pool_by_uuid(@storage_pool_uuid)
      vol = pool.lookup_volume_by_name("#{@name}.#{@format}")
      vol.delete

      ok
    end
  end
end
