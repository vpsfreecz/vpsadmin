template do
  label        'User account enters soft_delete'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Ukončení členství <%= @user.login %>'
end
