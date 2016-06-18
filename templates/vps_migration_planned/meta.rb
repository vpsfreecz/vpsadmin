template do
  label        'VPS migration planned'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] VPS #<%= @vps.id %> bude přesunuto na <%= @dst_node.domain_name %>'
  end

  lang :en do
    subject    '[vpsFree.cz] VPS #<%= @vps.id %> will be migrated to <%= @dst_node.domain_name %>'
  end
end
