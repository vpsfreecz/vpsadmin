template :outage_report_role_event do
  label 'User outage report update'

  lang :en do
    subject "Re: [<%= @o.outage_type_label %> Report] <%= @o.outage_entities.map { |e| e.real_name }.join(', ') %> - <%= local_time(@o.begins_at, '%Y-%m-%d %H:%M %Z') %>"
  end
end
