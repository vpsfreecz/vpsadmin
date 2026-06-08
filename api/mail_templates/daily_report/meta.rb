template :daily_report do
  label 'Daily report'

  lang :en do
    subject "[vpsAdmin] Daily report <%= local_time(@date[:start], '%Y-%m-%d') %>"
  end
end
