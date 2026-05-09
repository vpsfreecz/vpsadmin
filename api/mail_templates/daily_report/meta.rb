template :daily_report do
  label 'Daily report'

  lang :en do
    subject "[vpsAdmin] Daily report <%= @date[:start].localtime.strftime('%Y-%m-%d') %>"
  end
end
