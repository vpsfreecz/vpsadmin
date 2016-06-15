template do
  label        'Daily report for admins'
  from         'vpsadmin@vpsfree.cz'
  subject      'vpsAdmin daily report <%= @date[:start].strftime("%d/%m/%Y") %>'
end
