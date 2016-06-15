template do
  label        'VPS migration begun'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Právě začala migrace VPS #<%= @vps.id %> na <%= @dst_node.domain_name %>'
end
