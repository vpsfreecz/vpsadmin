template :outage_report_role do
  label 'Generic outage report'

  lang :en do
    subject '[vpsAdmin] Outage report #<%= @o.id %>'
  end
end
