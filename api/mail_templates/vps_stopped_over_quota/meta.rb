template :vps_stopped_over_quota do
  label 'VPS stopped over quota'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> stopped because of dataset quota'
  end
end
