class OutageUser < OutageVps
  def user
    vps.user
  end
end
