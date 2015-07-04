module VpsAdmin::API::Tasks
  class Mail < Base
    def daily_report
      TransactionChains::Mail::DailyReport.fire
    end
  end
end
