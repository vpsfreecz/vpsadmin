TransactionChains::Mail::DailyReport.connect_hook(:send) do |ret, _from, _now|
  ret[:base_url] = ::SysConfig.get('webui', 'base_url')
  ret
end
