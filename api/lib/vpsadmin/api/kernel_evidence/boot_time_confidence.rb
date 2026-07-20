module VpsAdmin::API::KernelEvidence
  module BootTimeConfidence
    ESTIMATED_COMPONENT = 'booted_at'.freeze
    ESTIMATED_REASON = 'estimated_from_uptime'.freeze

    module_function

    def from_report(report)
      return :incomplete unless report.kernel.booted_at

      estimated?(report.errors) ? :inferred : :exact
    end

    def estimated?(errors)
      errors.any? do |error|
        error.component == ESTIMATED_COMPONENT && error.reason == ESTIMATED_REASON
      end
    end
  end
end
