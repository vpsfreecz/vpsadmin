# frozen_string_literal: true

require 'openssl'

module TransactionKeyHelpers
  module_function

  TEST_PASSPHRASE = 'testpass'

  def install_encrypted_transaction_key!
    rsa = OpenSSL::PKey::RSA.new(2048)
    cipher = OpenSSL::Cipher.new('aes-256-cbc')

    pem = rsa.export(cipher, TEST_PASSPHRASE)

    rec = SysConfig.where(category: 'core', name: 'transaction_key').first_or_initialize
    rec.value = pem
    rec.data_type = 'Text' if rec.respond_to?(:data_type=) && rec.data_type.nil?
    rec.label = 'Transaction key' if rec.respond_to?(:label=) && rec.label.nil?
    rec.description = 'Spec key' if rec.respond_to?(:description=) && rec.description.nil?
    rec.min_user_level = 99 if rec.respond_to?(:min_user_level=) && rec.min_user_level.nil?
    rec.save!
  end

  def reset_transaction_signer!
    return unless defined?(::VpsAdmin::API::TransactionSigner)

    signer = ::VpsAdmin::API::TransactionSigner.instance
    %i[@key @pkey @unlocked].each do |ivar|
      signer.instance_variable_set(ivar, nil) if signer.instance_variable_defined?(ivar)
    end
  end

  def signer_locked?
    return true unless defined?(::VpsAdmin::API::TransactionSigner)

    signer = ::VpsAdmin::API::TransactionSigner.instance

    return signer.locked? if signer.respond_to?(:locked?)

    if signer.instance_variable_defined?(:@key)
      signer.instance_variable_get(:@key).nil?
    elsif signer.instance_variable_defined?(:@pkey)
      signer.instance_variable_get(:@pkey).nil?
    else
      true
    end
  end
end
