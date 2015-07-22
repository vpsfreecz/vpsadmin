template do
  label        'VPS resumed'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Obnovení VPS #<%= @vps.id %>'
end
