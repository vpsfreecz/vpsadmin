template :request_action_role do
  label 'Resolve request (admin)'

  lang :en do
    subject 'Re: [vpsAdmin Request #<%= @r.id %> <%= @r.type_name %>] <%= @r.state %>'
  end
end
