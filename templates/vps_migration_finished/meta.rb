template do
  label        'VPS migration finished'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Migrace VPS #<%= @vps.id %> na <%= @dst_node.domain_name %> byla dokončena'
end
