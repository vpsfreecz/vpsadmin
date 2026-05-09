template :alert_user_zombie_processes_state do
  label 'Zombie processes alert'

  lang :en do
    subject '[vpsAdmin] Zombie processes detected on <%= @vps.hostname %>'
  end
end
