template :outage_report_role_event do
  label 'Generic outage report update'

  lang :en do
    subject "Re: <%= @o.outage_type_label %> - <%= @o.outage_entities.map { |e| e.real_name }.join(', ') %> - <%= local_time(@o.begins_at, '%Y-%m-%d %H:%M %Z') %>"
  end
end
