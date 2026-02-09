# frozen_string_literal: true

module GlobalReset
  module_function

  def reset!
    reset_current_user!
    reset_current_session!
    reset_papertrail!
    reset_transaction_signer!
  end

  def reset_current_user!
    return unless defined?(::User)
    return unless ::User.respond_to?(:current=)

    ::User.current = nil
  rescue StandardError
    # ignore
  end

  def reset_current_session!
    return unless defined?(::UserSession)
    return unless ::UserSession.respond_to?(:current=)

    ::UserSession.current = nil
  rescue StandardError
    # ignore
  end

  def reset_papertrail!
    return unless defined?(::PaperTrail)
    return unless ::PaperTrail.respond_to?(:request)

    if ::PaperTrail.request.respond_to?(:whodunnit=)
      ::PaperTrail.request.whodunnit = nil
    end
  rescue StandardError
    # ignore
  end

  def reset_transaction_signer!
    return unless defined?(::VpsAdmin::API::TransactionSigner)

    signer = ::VpsAdmin::API::TransactionSigner.instance
    %i[@key @pkey @unlocked].each do |ivar|
      signer.instance_variable_set(ivar, nil) if signer.instance_variable_defined?(ivar)
    end
  rescue StandardError
    # ignore
  end
end

RSpec.configure do |config|
  config.after do
    GlobalReset.reset!

    if respond_to?(:header)
      header 'Authorization', nil
    end
  end
end
