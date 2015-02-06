VpsAdmin::API::DatasetPlans.register do
  plan :daily_backup, label: 'Daily backup' do |dip|
    group_snapshot dip, '00', '01', '*', '*', '*'
    backup dip, '05', '01', '*', '*', '*'
  end
end
