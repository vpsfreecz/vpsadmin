module VpsAdmin::API::Plugins::Cop::TransactionChains
  class ReportViolation < ::TransactionChain
    label 'Report'

    def link_chain(violations)
      mail(:policy_violation, {
          language: ::Language.take!,
          vars: {
              violations: violations,
          }
      })
    end
  end
end
