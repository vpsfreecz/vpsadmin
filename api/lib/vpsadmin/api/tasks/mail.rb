module VpsAdmin::API::Tasks
  class Mail < Base
    # Mail daily report to administrators.
    #
    # Accepts the following environment variables:
    # [VPSADMIN_LANG]: Language in which to send the daily report,
    #                  defaults to 'en'
    def daily_report
      lang = ::Language.find_by!(code: ENV['VPSADMIN_LANG'] || 'en')
      TransactionChains::Mail::DailyReport.fire(lang)
    end
  end
end
