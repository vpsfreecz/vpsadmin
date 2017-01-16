module Transactions::Vps
  class DeployPublicKey < ::Transaction
    t_name :vps_deploy_public_key
    t_type 2017
    queue :vps

    def params(vps, pubkey)
      self.vps_id = vps.vps_id
      self.node_id = vps.vps_server

      {pubkey: pubkey.key}
    end
  end
end
