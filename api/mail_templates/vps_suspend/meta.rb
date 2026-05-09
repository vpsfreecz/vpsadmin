template :vps_suspend do
  label 'VPS suspended'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> has been suspended'
  end
end
