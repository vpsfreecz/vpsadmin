template :vps_dns_resolver_change do
  label 'VPS DNS resolver changed'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> DNS resolver changed'
  end
end
