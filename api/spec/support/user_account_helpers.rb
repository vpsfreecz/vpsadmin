# frozen_string_literal: true

module UserAccountHelpers
  def mark_user_paid_until!(user, paid_until = 1.month.from_now)
    return unless user.respond_to?(:user_account)

    user.user_account&.update!(paid_until: paid_until)
  end
end

RSpec.configure do |config|
  config.include UserAccountHelpers
end
