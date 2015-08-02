module Transactions::Vps
  class Passwd < ::Transaction
    t_name :vps_passwd
    t_type 2002
    queue :vps

    def params(vps, passwd)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      {
          user: 'root',
          password: passwd
      }
    end
  end
end
