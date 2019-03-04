require_relative 'outage_vps'

class OutageUser < OutageVps
  def user
    vps.user
  end
end
