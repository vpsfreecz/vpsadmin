template do
  label        'VPS resources changed'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Změna parametrů VPS <%= @vps.id %>'
  end

  lang :en do
    subject    '[vpsFree.cz] Change of limits for VPS <%= @vps.id %>'
  end
end
