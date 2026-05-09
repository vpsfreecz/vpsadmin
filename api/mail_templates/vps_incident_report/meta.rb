template :vps_incident_report do
  label 'VPS incident report'

  lang :en do
    subject '[vpsAdmin] Incident report for VPS <%= @vps.hostname %>'
  end
end
