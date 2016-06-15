template do
  label        'VPS suspended'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Pozastavení VPS #<%= @vps.id %>'
end
