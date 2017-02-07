template :request_create_admin do
  label        'Create request (admin)'
  from         'podpora@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :en do
    subject    '[vpsAdmin Request #<%= @r.id %> <%= @r.type_name %>] <%= @r.state %>'
  end
end
