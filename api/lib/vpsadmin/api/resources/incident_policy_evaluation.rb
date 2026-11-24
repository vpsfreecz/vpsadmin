module VpsAdmin::API::Resources
  class IncidentPolicyEvaluation < HaveAPI::Resource
    desc 'Saved incident policy evaluations and the latest action outcomes'

    params(:all) do
      integer :id, label: 'ID'
      integer :incident_report_id, label: 'Source incident report ID'
      integer :vps_id, nullable: true, label: 'Original VPS ID'
      integer :user_id, nullable: true, label: 'Original owner ID'
      string :hostname, nullable: true, label: 'Hostname'
      string :user_login, nullable: true, label: 'Owner login'
      string :policy_key, label: 'Policy key'
      string :label, label: 'Policy name'
      datetime :evaluated_at, label: 'Policy evaluated at'
      datetime :detected_at, nullable: true, label: 'Incident detected at'
      bool :matched, nullable: true, label: 'Matched policy'
      string :state, choices: { values: { 'recorded' => 'recorded', 'skipped' => 'skipped', 'error' => 'error', 'audit_only' => 'audit only' } }, label: 'Evaluation state'
      integer :warning_period_days, label: 'Warning period in days'
      integer :stop_period_days, label: 'Shutdown period in days'
      integer :count_7d, nullable: true, label: 'Incidents in 7 days'
      integer :count_30d, nullable: true, label: 'Incidents in 30 days'
      integer :warning_limit, nullable: true, label: 'Warning limit'
      integer :stop_limit, nullable: true, label: 'Shutdown limit'
      string :effective_mode, choices: { values: { 'observe' => 'Observation only', 'notify' => 'Warnings only', 'enforce' => 'Automatic shutdown permitted' } }, nullable: true, label: 'Effective mode'
      bool :stop_enforced, nullable: true, label: 'Automatic shutdown permitted'
      string :threshold_status, choices: { values: { 'clear' => 'Below thresholds', 'near_limit' => 'Near a threshold', 'warning' => 'Warning threshold reached', 'stop_threshold' => 'Shutdown threshold reached' } }, nullable: true, label: 'Saved threshold status'
      string :decision, choices: { values: { 'none' => 'No action', 'warning' => 'Warning', 'stop' => 'Shutdown' } }, label: 'Decision'
      integer :action_id, nullable: true, label: 'Action ID'
      string :action_kind, choices: { values: { 'warning' => 'Warning', 'stop' => 'Shutdown' } }, nullable: true, label: 'Action kind'
      string :action_state, choices: { values: { 'pending' => 'Pending', 'queued' => 'Queued', 'failed' => 'Failed', 'uncertain' => 'Outcome uncertain', 'completed' => 'Completed', 'suppressed' => 'Suppressed' } }, nullable: true, label: 'Action state'
      datetime :action_created_at, nullable: true, label: 'Action created at'
      datetime :action_updated_at, nullable: true, label: 'Action last updated at'
      integer :transaction_chain_id, nullable: true, label: 'Transaction chain ID'
      integer :physical_stop_action_id, nullable: true, label: 'Shared VPS shutdown action ID'
      datetime :stop_completed_at, nullable: true, label: 'Confirmed shutdown', desc: 'Confirmed VPS shutdown, independent of warning completion or email delivery.'
      integer :notice_report_id, nullable: true, label: 'Notice report ID'
      string :mail_state, choices: { values: { 'pending' => 'Not yet queued', 'queued' => 'Queued for sending', 'sent' => 'Accepted by mail server', 'failed' => 'Sending failed', 'uncertain' => 'Sending outcome uncertain', 'suppressed' => 'Sending suppressed' } }, nullable: true, label: 'Email state', desc: 'Sent means acceptance by the mail server, without proof of inbox delivery.'
      datetime :mail_queued_at, nullable: true, label: 'Email queued at'
      datetime :mail_finished_at, nullable: true, label: 'Email attempt finished at'
    end

    class Index < HaveAPI::Action
      include VpsAdmin::API::IncidentPolicyReadAction

      desc 'List saved evaluations with the latest action and email outcomes'

      input do
        string :policy_key, label: 'Policy key'
        integer :vps_id, label: 'Original VPS ID'
        integer :user_id, label: 'Original owner ID'
        string :decision, choices: { values: { 'none' => 'No action', 'warning' => 'Warning', 'stop' => 'Shutdown' } }, label: 'Decision'
        string :action_kind, choices: { values: { 'warning' => 'Warning', 'stop' => 'Shutdown' } }, label: 'Action kind'
        string :action_state, choices: { values: { 'pending' => 'Pending', 'queued' => 'Queued', 'failed' => 'Failed', 'uncertain' => 'Outcome uncertain', 'completed' => 'Completed', 'suppressed' => 'Suppressed' } }, label: 'Action state'
        string :mail_state, choices: { values: { 'pending' => 'Not yet queued', 'queued' => 'Queued for sending', 'sent' => 'Accepted by mail server', 'failed' => 'Sending failed', 'uncertain' => 'Sending outcome uncertain', 'suppressed' => 'Sending suppressed' } }, label: 'Email state', desc: 'Sent means acceptance by the mail server, without proof of inbox delivery.'
        string :scope, choices: { values: { 'violations' => 'Reached thresholds and actions', 'matched' => 'All saved matches', 'all' => 'All evaluations', 'outstanding' => 'Unresolved actions and emails' } }, default: 'violations', fill: true, label: 'History scope'
        datetime :from, label: 'Period start (inclusive)', desc: 'The period includes its start and excludes its end. Ignored for outstanding actions.'
        datetime :to, label: 'Period end (exclusive)', desc: 'The period includes its start and excludes its end. Ignored for outstanding actions.'
        string :direction, choices: { values: { 'asc' => 'Ascending', 'desc' => 'Descending' } }, default: 'desc', fill: true, label: 'Direction'
      end
      meta(:global) do
        output do
          datetime :from, nullable: true, label: 'Period start (inclusive)', desc: 'The period includes its start and excludes its end. Ignored for outstanding actions.'
          datetime :to, nullable: true, label: 'Period end (exclusive)', desc: 'The period includes its start and excludes its end. Ignored for outstanding actions.'
        end
      end
      output(:object_list) { use :all }

      def exec = projected(:history)
    end
  end
end
