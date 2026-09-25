require 'nodectld/storage_inventory'

module NodeCtld
  class Commands::Storage::Inventory < Commands::Base
    handle 5290

    def exec
      result = StorageInventory.run!(
        @command, {
          run_uuid: @run_uuid, attempt_uuid: @attempt_uuid,
          node_id: @node_id, pool_id: @pool_id, zpool: @zpool,
          zpool_guid: @zpool_guid, managed_root: @managed_root,
          roots: @roots, routing_key: @routing_key, nonce: @nonce,
          deadline: @deadline, protocol_version: @protocol_version
        }
      )
      @output.merge!(result)
      ok
    end
  end
end
