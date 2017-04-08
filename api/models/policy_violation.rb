class PolicyViolation < ActiveRecord::Base
  has_many :policy_violation_logs
  enum state: %i(monitoring confirmed unconfirmed ignored)

  # TODO: optimize by fetch all monitored violations in advance
  def self.report!(policy, obj, value, passed)
    attrs = {
        policy: policy.name,
        class_name: obj.class.name,
        row_id: obj.id,
        state: states[:monitoring],
    }

    transaction do
      violation = self.find_by(attrs)

      if violation.nil?
        break if passed
        
        violation = self.create!(attrs)
      end

      violation.policy_violation_logs << PolicyViolationLog.new(
          passed: passed,
          value: value,
      )

      if passed
        violation.update!(state: states[:unconfirmed])
        break
      end
      
      if (Time.now - violation.created_at) >= policy.period
        violation.update!(state: states[:confirmed])
        # TODO: invoke configured action, i.e. notify admins
      end
    end
  end
end
