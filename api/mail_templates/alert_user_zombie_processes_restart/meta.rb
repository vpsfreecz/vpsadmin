template :alert_user_zombie_processes_restart do
  label 'Zombie processes restart'

  lang :en do
    subject '[vpsAdmin] VPS <%= @vps.hostname %> restart planned'
  end
end
