module TransactionChains
  class User::ReportFailedLogins < ::TransactionChain
    label 'Failed logins'

    # @param user_attempt_groups [Hash<User, Array<Array<UserFailedLogin>>>]
    def link_chain(user_attempt_groups)
      concerns(
        :affect,
        *(user_attempt_groups.each_key.map { |u| [u.class.name, u.id] })
      )

      now = Time.now

      user_attempt_groups.each do |user, attempt_groups|
        mail(:user_failed_logins, {
          user:,
          vars: {
            user:,
            attempt_groups:
          }
        })

        ::UserFailedLogin
          .where(id: attempt_groups.map { |grp| grp.map(&:id) }.flatten)
          .update_all(reported_at: now)
      end
    end
  end
end
