template do
  label        'VPS expiration notification'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Expirace VPS #<%= @vps.id %> <%= @vps.hostname %>'
end
