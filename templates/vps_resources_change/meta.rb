template do
  label        'VPS resources changed'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Změna parametrů VPS <%= @vps.id %>'
end
