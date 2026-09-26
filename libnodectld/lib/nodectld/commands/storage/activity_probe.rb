require 'nodectld/storage_activity_probe'

module NodeCtld
  class Commands::Storage::ActivityProbe < Commands::Base
    handle 5291

    def exec
      result = StorageActivityProbe.run!(@command, {
        protocol_version: @protocol_version, request_uuid: @request_uuid,
        attempt_uuid: @attempt_uuid, nonce: @nonce, node_id: @node_id,
        freeze_epoch: @freeze_epoch, deadline: @deadline, claims: @claims
      })
      @output.merge!(result)
      ok
    end
  end
end
