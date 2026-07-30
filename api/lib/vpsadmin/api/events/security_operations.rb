# frozen_string_literal: true

module VpsAdmin::API::Events::SecurityOperations
  module_function

  def emit_failed_login!(attempt)
    VpsAdmin::API::Events.emit!(
      'user.login_failed',
      user: attempt.user,
      source: attempt,
      subject: 'Failed sign-in attempt',
      summary: failed_login_summary(attempt),
      payload: {
        failed_login_id: attempt.id,
        auth_type: attempt.auth_type,
        reason: attempt.reason,
        api_ip_addr: attempt.api_ip_addr,
        client_ip_addr: attempt.client_ip_addr,
        client_version: attempt.client_version,
        failed_at: attempt.created_at&.iso8601
      }.compact,
      ip_addr: attempt.client_ip_addr || attempt.api_ip_addr,
      occurred_at: attempt.created_at
    )
  end

  def failed_login_summary(attempt)
    source = attempt.client_ip_addr || attempt.api_ip_addr || 'an unknown address'
    "A #{attempt.auth_type} sign-in failed from #{source}: #{attempt.reason}"
  end
end

VpsAdmin::API::Events.define do
  event 'user.login_failed',
        label: 'Failed sign-in',
        category: 'security',
        severity: :warning,
        roles: %i[account admin],
        default_routed: false,
        examples: {
          subject: 'Failed sign-in attempt',
          summary: 'A password sign-in failed from 198.51.100.10: invalid password'
        } do
    fields(
      failed_login_id: {
        description: 'ID of the recorded failed sign-in attempt',
        type: :integer
      },
      auth_type: {
        description: 'Authentication method used by the failed sign-in',
        type: :string,
        example: 'password'
      },
      reason: {
        description: 'Reason why authentication failed',
        type: :string,
        example: 'invalid password'
      },
      api_ip_addr: {
        description: 'IP address observed by the vpsAdmin API',
        type: :string
      },
      client_ip_addr: {
        description: 'Client IP address reported to the vpsAdmin API',
        type: :string
      },
      client_version: {
        description: 'Version or user-agent string reported by the client',
        type: :string,
        example: 'vpsfree-client/1.0'
      },
      failed_at: {
        description: 'Time when the failed sign-in was recorded',
        type: :datetime
      }
    )
  end
end
