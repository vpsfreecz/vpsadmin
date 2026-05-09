template :vps_migration_begun do
  label 'VPS migration begun'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> migration started'
  end
end
