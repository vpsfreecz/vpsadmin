# frozen_string_literal: true

require 'securerandom'

module PluginRequestsSpecHelpers
  Response = Struct.new(:data) do
    def success? = data[:success] == true
    def [](key) = data[key]
  end

  def ipqs_response(hash)
    Response.new(hash)
  end

  def unique_request_login(prefix = 'request')
    "#{prefix}-#{SecureRandom.hex(4)}"
  end

  def build_registration_request!(attrs = {})
    RegistrationRequest.new({
      user: attrs.fetch(:user, SpecSeed.user),
      state: attrs.fetch(:state, :awaiting),
      api_ip_addr: attrs.fetch(:api_ip_addr, '192.0.2.11'),
      api_ip_ptr: attrs.fetch(:api_ip_ptr, 'ptr-192.0.2.11'),
      client_ip_addr: attrs[:client_ip_addr],
      client_ip_ptr: attrs[:client_ip_ptr],
      login: attrs.fetch(:login, unique_request_login('reg')),
      full_name: attrs.fetch(:full_name, 'Spec Registrant'),
      email: attrs.fetch(:email, 'registrant@test.invalid'),
      address: attrs.fetch(:address, 'Spec Address 1'),
      year_of_birth: attrs.fetch(:year_of_birth, 1990),
      os_template: attrs.fetch(:os_template, SpecSeed.os_template),
      location: attrs.fetch(:location, SpecSeed.location),
      currency: attrs.fetch(:currency, 'eur'),
      language: attrs.fetch(:language, SpecSeed.language),
      last_mail_id: attrs.fetch(:last_mail_id, 0),
      ip_checked: attrs[:ip_checked],
      mail_checked: attrs[:mail_checked]
    }.compact).tap(&:save!)
  end

  def build_change_request!(attrs = {})
    ChangeRequest.new({
      user: attrs.fetch(:user, SpecSeed.user),
      state: attrs.fetch(:state, :awaiting),
      api_ip_addr: attrs.fetch(:api_ip_addr, '192.0.2.10'),
      api_ip_ptr: attrs.fetch(:api_ip_ptr, 'ptr-192.0.2.10'),
      change_reason: attrs.fetch(:change_reason, 'Need update'),
      full_name: attrs.fetch(:full_name, 'Spec User'),
      email: attrs[:email],
      address: attrs[:address],
      last_mail_id: attrs.fetch(:last_mail_id, 0)
    }.compact).tap(&:save!)
  end

  def ensure_request_notification_template!(name, template_id)
    template = NotificationTemplate.find_or_create_by!(name:) do |tpl|
      tpl.label = name.tr('_', ' ').capitalize
      tpl.template_id = template_id
    end

    return if template.notification_template_variants.where(language: SpecSeed.language, protocol: :email).exists?

    template.notification_template_variants.create!(
      language: SpecSeed.language,
      protocol: :email,
      from: 'noreply@test.invalid',
      subject: "#{name} subject",
      text: "#{name} body"
    )
  end
end

RSpec.configure do |config|
  config.include PluginRequestsSpecHelpers
end
