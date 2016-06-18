template do
  label        'VPS resumed'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Obnovení VPS #<%= @vps.id %>'
  end

  lang :en do
    subject    '[vpsFree.cz] VPS #<%= @vps.id %> resumed'
  end
end
