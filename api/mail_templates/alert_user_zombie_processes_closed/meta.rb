template :alert_user_zombie_processes_state do
  label 'Zombie processes alert closed'

  lang :en do
    subject '[vpsAdmin] Zombie process alert closed for <%= @vps.hostname %>'
  end
end
