TransactionChains::Mail::DailyReport.connect_hook(:send) do |ret, from, now|
  ret[:base_url] = ::SysConfig.get('webui', 'base_url')
  ret
end
