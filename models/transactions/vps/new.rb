module Transactions::Vps
  class New < ::Transaction
    t_name :vps_new
    t_type 3001

    def prepare(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          hostname: vps.hostname,
          template: 'scientific-6-x86_64', # fixme
          onboot: true, # fixme
          nameserver: '8.8.8.8', # fixme
      }
    end
  end
end
