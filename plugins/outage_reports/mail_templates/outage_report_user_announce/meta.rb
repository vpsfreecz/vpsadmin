template :outage_report_role_event do
  label 'User outage report announcement'

  lang :en do
    subject "[<%= @o.outage_type_label %> Report] <%= @o.outage_entities.map { |e| e.real_name }.join(', ') %> - <%= @o.begins_at.localtime.strftime('%Y-%m-%d %H:%M %Z') %>"
  end
end
