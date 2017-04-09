template do
  label        'Policy violation report'
  from         'vpsadmin@vpsfree.cz'
  subject      'Policy violation report: <%= @violations.count %> new violations'
end
