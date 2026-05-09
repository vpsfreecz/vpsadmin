template :outage_report_role do
  label 'User outage report'

  lang :en do
    subject '[vpsAdmin] Outage report #<%= @o.id %>'
  end
end
