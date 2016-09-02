class IpRecentTraffic < ActiveRecord::Base
  belongs_to :ip_address
  belongs_to :user

  enum protocol: %i(proto_all proto_tcp proto_udp)
end
