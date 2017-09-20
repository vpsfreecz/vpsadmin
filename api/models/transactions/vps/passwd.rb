module Transactions::Vps
  class Passwd < ::Transaction
    t_name :vps_passwd
    t_type 2002
    queue :vps

    def params(vps, passwd)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
          user: 'root',
          password: passwd
      }
    end
  end
end
