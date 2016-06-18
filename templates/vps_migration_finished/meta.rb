template do
  label        'VPS migration finished'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Migrace VPS #<%= @vps.id %> na <%= @dst_node.domain_name %> byla dokončena'
  end

  lang :en do
    subject    '[vpsFree.cz] Migration of VPS #<%= @vps.id %> to <%= @dst_node.domain_name %> was finished'
  end
end
