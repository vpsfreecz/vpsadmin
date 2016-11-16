module Transactions::Vps
  class DeployPublicKey < ::Transaction
    t_name :vps_deploy_public_key
    t_type 2017
    queue :vps

    def params(vps, pubkey)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {pubkey: pubkey.key}
    end
  end
end
