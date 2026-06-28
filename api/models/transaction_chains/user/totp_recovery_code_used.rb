module TransactionChains
  class User::TotpRecoveryCodeUsed < ::TransactionChain
    label 'TOTP recovery'
    allow_empty

    def link_chain(user, totp_device, request)
      concerns(:affect, [user.class.name, user.id])

      used_at = Time.now
      request_ip = request.respond_to?(:ip) ? request.ip : nil

      route_event!(
        'user.totp_recovery_code_used',
        user:,
        source: totp_device,
        subject: 'TOTP recovery code used',
        summary: "TOTP recovery code used for #{user.login}",
        parameters: {
          totp_device_id: totp_device.id,
          totp_device_label: totp_device.label,
          request_ip:,
          used_at: used_at.iso8601
        },
        ip_addr: request_ip
      )
    end
  end
end
