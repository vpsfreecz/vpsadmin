# frozen_string_literal: true

module AuthHelpers
  def api_login(user, password: 'secret')
    header 'User-Agent', 'RSpec'
    basic_authorize(user.login, password)
  end

  def clear_login
    header 'Authorization', nil
  end

  def as(user, password: 'secret')
    api_login(user, password: password)
    yield
  ensure
    clear_login
  end
end

RSpec.configure do |config|
  config.include AuthHelpers
end
