template do
  label        'Payment notification'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'

  lang :cs do
    subject    '[vpsFree.cz] Platba členského příspěvku - <%= @object.login %>'
  end

  lang :en do
    subject    '[vpsFree.cz] Payment of membership fee - <%= @object.login %>'
  end
end
