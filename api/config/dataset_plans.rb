VpsAdmin::API::DatasetPlans.register do
  plan :daily_backup, label: 'Daily backup',
        desc: 'Snapshot every day at 01:00 and backup on backuper.prg' do |dip|
    group_snapshot dip, '00', '01', '*', '*', '*'
    backup dip, '05', '01', '*', '*', '*'
  end
end
