template do
  label        'VPS suspended'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Pozastavení VPS #<%= @vps.id %>'
  end

  lang :en do
    subject    '[vpsFree.cz] VPS #<%= @vps.id %> was suspended'
  end
end
