module Transactions::Vps
  class Passwd < ::Transaction
    t_name :vps_passwd
    t_type 2002

    def prepare(vps, passwd)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          user: 'root',
          password: passwd
      }
    end
  end
end
