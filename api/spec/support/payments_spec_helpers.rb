# frozen_string_literal: true

module PaymentsSpecHelpers
  def seed_payments_sysconfig!(
    default_currency: 'CZK',
    conversion_rates: {},
    payment_instructions: nil
  )
    SysConfig.find_by!(category: 'plugin_payments', name: 'default_currency')
             .update!(value: default_currency)

    SysConfig.find_by!(category: 'plugin_payments', name: 'conversion_rates')
             .update!(value: conversion_rates)

    return unless payment_instructions

    SysConfig.find_by!(category: 'plugin_payments', name: 'payment_instructions')
             .update!(value: payment_instructions)
  end
end

RSpec.configure do |config|
  config.include PaymentsSpecHelpers
end
