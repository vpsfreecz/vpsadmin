template :expiration_warning do
  label 'VPS expiration warning'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> is nearing expiration'
  end
end
