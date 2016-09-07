class IpTrafficMonthlySummary < ActiveRecord::Base
  belongs_to :ip_address
  belongs_to :user

  enum protocol: %i(proto_other proto_tcp proto_udp)
  enum role: %i(role_public role_private)

  def api_role
    role['role_'.size..-1]
  end
end
