template do
  label        'VPS expiration notification'
  from         'podpora@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Expirace VPS #<%= @vps.id %> <%= @vps.hostname %>'
  end

  lang :en do
    subject    '[vpsFree.cz] Expiration of VPS #<%= @vps.id %> <%= @vps.hostname %>'
  end
end
