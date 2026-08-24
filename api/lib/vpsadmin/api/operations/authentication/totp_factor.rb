require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::TotpFactor < Operations::Base
    Result = Data.define(:device, :last_verification_at, :recovery_code) do
      def recovery_code?
        recovery_code
      end
    end

    # The caller must hold the user row lock. Eligible factor rows are locked
    # before their proof state is checked and updated.
    def run(user, code)
      user.user_totp_devices.where(
        enabled: true,
        confirmed: true
      ).order('last_use_at DESC').lock.each do |device|
        last_verification_at = device.totp.verify(
          code,
          after: device.last_verification_at
        )
        recovery_code = recovery_code?(device, code)
        next unless last_verification_at || recovery_code

        if last_verification_at
          device.update!(
            last_verification_at:,
            last_use_at: Time.current,
            use_count: device.use_count + 1
          )
        else
          device.update!(enabled: false)
        end

        return Result.new(
          device:,
          last_verification_at:,
          recovery_code:
        )
      end

      nil
    end

    protected

    def recovery_code?(device, code)
      CryptoProviders::Bcrypt.matches?(device.recovery_code, nil, code)
    end
  end
end
