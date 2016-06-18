template do
  label        'VPS migration begun'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Právě začala migrace VPS #<%= @vps.id %> na <%= @dst_node.domain_name %>'
  end

  lang :en do
    subject    '[vpsFree.cz] Migration of VPS #<%= @vps.id %> to <%= @dst_node.domain_name %> has begun'
  end
end
