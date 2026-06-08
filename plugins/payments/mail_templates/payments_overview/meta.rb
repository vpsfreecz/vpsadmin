template :payments_overview do
  label 'Payments overview'

  lang :en do
    subject "[vpsAdmin] Payments overview <%= local_time(@start, '%Y-%m-%d %H:%M') %> - <%= local_time(@end, '%Y-%m-%d %H:%M') %>"
  end
end
