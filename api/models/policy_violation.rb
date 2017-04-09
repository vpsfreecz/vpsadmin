class PolicyViolation < ActiveRecord::Base
  has_many :policy_violation_logs
  enum state: %i(monitoring confirmed unconfirmed ignored)

  attr_accessor :policy, :object

  # TODO: optimize by fetch all monitored violations in advance
  def self.report!(policy, obj, value, passed)
    attrs = {
        policy_name: policy.name,
        class_name: obj.class.name,
        row_id: obj.id,
        state: states[:monitoring],
    }

    transaction do
      violation = self.find_by(attrs)

      if violation.nil?
        next if passed

        if policy.cooldown
          # Find last confirmed violation of the same type
          last = self.find_by(
              policy_name: policy.name,
              class_name: obj.class.name,
              row_id: obj.id,
              state: states[:confirmed],
          )

          next if last && (last.closed_at + policy.cooldown) >= Time.now
        end

        violation = self.create!(attrs)
      end

      violation.policy_violation_logs << PolicyViolationLog.new(
          passed: passed,
          value: value,
      )

      if passed
        violation.update!(state: states[:unconfirmed], closed_at: Time.now)
        next
      end

      if (Time.now - violation.created_at) >= policy.period
        violation.update!(state: states[:confirmed], closed_at: Time.now)
        violation.policy = policy
        violation.object = obj
        next violation
      end

      nil
    end
  end
end
