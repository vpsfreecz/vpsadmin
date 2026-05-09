template :payments_overview do
  label 'Payments overview'

  lang :en do
    subject "[vpsAdmin] Payments overview <%= @start.localtime.strftime('%Y-%m-%d %H:%M') %> - <%= @end.localtime.strftime('%Y-%m-%d %H:%M') %>"
  end
end
