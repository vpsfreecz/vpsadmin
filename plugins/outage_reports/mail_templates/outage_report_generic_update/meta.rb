template :outage_report_role_event do
  label 'Generic outage report update'

  lang :en do
    subject "Re: <%= @o.outage_type.capitalize %> - <%= @o.outage_entities.map { |e| e.real_name }.join(', ') %> - <%= @o.begins_at.localtime.strftime('%Y-%m-%d %H:%M %Z') %>"
  end
end
