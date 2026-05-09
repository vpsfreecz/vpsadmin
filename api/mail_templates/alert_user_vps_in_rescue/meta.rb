template :alert_user_vps_in_rescue do
  label 'VPS in rescue mode alert'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> is in rescue mode'
  end
end
