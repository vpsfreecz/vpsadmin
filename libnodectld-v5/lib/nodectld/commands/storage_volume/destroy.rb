module NodeCtld
  class Commands::StorageVolume::Destroy < Commands::Base
    handle 5232

    def exec
      conn = LibvirtClient.new
      pool = conn.lookup_storage_pool_by_uuid(@storage_pool_uuid)
      vol = pool.lookup_volume_by_name("#{@name}.#{@format}")
      vol.delete
      ok
    end
  end
end
