template :request_action_role do
  label 'Update request (admin)'

  lang :en do
    subject 'Re: [vpsAdmin Request #<%= @r.id %> <%= @r.type_name %>] <%= @r.state %>'
  end
end
