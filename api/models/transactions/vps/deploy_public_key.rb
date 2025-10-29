module Transactions::Vps
  class DeployPublicKey < ::Transaction
    t_name :vps_deploy_public_key
    t_type 2017
    queue :vps

    def params(vps, pubkey)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        vps_uuid: vps.uuid.uuid,
        pubkey: pubkey.key
      }
    end
  end
end
