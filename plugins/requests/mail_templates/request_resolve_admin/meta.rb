template :request_action_role do
  label        'Resolve request (admin)'
  from         'noreply@vpsadmin.invalid'
  reply_to     'support@vpsadmin.invalid'
  return_path  'noreply@vpsadmin.invalid'

  lang :en do
    subject '[vpsAdmin Request #<%= @r.id %> <%= @r.type_name %>] <%= @r.state %>'
  end
end
