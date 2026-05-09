template :vps_resume do
  label 'VPS resumed'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> has been resumed'
  end
end
