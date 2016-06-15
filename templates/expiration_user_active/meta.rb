template do
  label        'Payment notification'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Platba členského příspěvku - <%= @object.login %>'
end
