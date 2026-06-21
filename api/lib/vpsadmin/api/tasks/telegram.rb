module VpsAdmin::API::Tasks
  class Telegram < Base
    def poll_pairing_updates
      VpsAdmin::API::TelegramReceiver.new.poll_once
    end
  end
end
