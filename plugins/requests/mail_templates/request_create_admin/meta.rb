template :request_action_role do
  label 'Create request (admin)'

  lang :en do
    subject '[vpsAdmin Request #<%= @r.id %> <%= @r.type_name %>] <%= @r.state %>'
  end
end
