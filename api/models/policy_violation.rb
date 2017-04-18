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
          last = self.where(
              policy_name: policy.name,
              class_name: obj.class.name,
              row_id: obj.id,
              state: states[:confirmed],
          ).order('created_at DESC').take

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

      if policy.period.nil? && policy.check_count.nil?
        fail "Policy #{policy.name}: specify either period or check_count"

      elsif (policy.period && (Time.now - violation.created_at) >= policy.period) \
        || (policy.check_count && policy.check_count >= violation.check_count)
        violation.update!(state: states[:confirmed], closed_at: Time.now)
        violation.policy = policy
        violation.object = obj
        next violation
      end

      nil
    end
  end

  def check_count
    policy_violation_logs.count
  end
end
