module VpsAdmin::API::Resources
  class IncidentPolicyExposure < HaveAPI::Resource
    desc 'VPSes with currently counted incident policy matches'

    params(:all) do
      string :id, label: 'ID'
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::User, value_label: :login
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      string :policy_key, label: 'Policy key'
      string :label, label: 'Policy name'
      bool :owner_active, label: 'Owner active'
      bool :transfer_pending, label: 'Ownership transfer pending'
      integer :count_7d, label: 'Incidents in 7 days'
      integer :count_30d, label: 'Incidents in 30 days'
      integer :warning_period_days, label: 'Warning period in days'
      integer :stop_period_days, label: 'Shutdown period in days'
      integer :warning_limit, nullable: true, label: 'Warning limit'
      integer :stop_limit, nullable: true, label: 'Shutdown limit'
      integer :warning_remaining, nullable: true, label: 'Reports until warning threshold'
      integer :stop_remaining, nullable: true, label: 'Reports until shutdown threshold'
      bool :configuration_valid, label: 'Valid configuration'
      string :status, choices: { values: { 'clear' => 'Below thresholds', 'near_limit' => 'Near a threshold', 'warning' => 'Warning threshold reached', 'stop_threshold' => 'Shutdown threshold reached' } }, nullable: true, label: 'Threshold status'
      string :global_mode, label: 'Global mode'
      string :effective_mode, choices: { values: { 'observe' => 'Observation only', 'notify' => 'Warnings only', 'enforce' => 'Automatic shutdown permitted' } }, nullable: true, label: 'Effective mode'
      bool :warning_permitted, nullable: true, label: 'Warning emails allowed'
      bool :stop_enforced, nullable: true, label: 'Automatic shutdown permitted'
      datetime :last_incident_at, nullable: true, label: 'Last incident'
      datetime :last_warning_at, nullable: true, label: 'Last warning queued'
      datetime :next_warning_allowed_at, nullable: true, label: 'Warning cooldown ends'
      datetime :last_stop_at, nullable: true, label: 'Last confirmed shutdown'
      datetime :next_stop_allowed_at, nullable: true, label: 'Shutdown cooldown ends'
      datetime :accounting_since, nullable: true, label: 'Counting since'
      string :outstanding_stop_state, choices: { values: { 'none' => 'None', 'pending' => 'Pending', 'failed' => 'Failed', 'uncertain' => 'Outcome uncertain' } }, label: 'Outstanding shared shutdown state'
      integer :outstanding_stop_action_id, nullable: true, label: 'Outstanding shared shutdown action ID'
      integer :outstanding_stop_chain_id, nullable: true, label: 'Outstanding shared shutdown transaction chain ID'
      integer :latest_action_id, nullable: true, label: 'Latest action ID'
      integer :latest_action_chain_id, nullable: true, label: 'Latest action transaction chain ID'
      integer :latest_notice_report_id, nullable: true, label: 'Latest notice report ID'
      string :latest_action_kind, choices: { values: { 'warning' => 'Warning', 'stop' => 'Shutdown' } }, nullable: true, label: 'Latest action kind'
      string :latest_action_state, choices: { values: { 'pending' => 'Pending', 'queued' => 'Queued', 'failed' => 'Failed', 'uncertain' => 'Outcome uncertain', 'completed' => 'Completed', 'suppressed' => 'Suppressed' } }, nullable: true, label: 'Latest action state'
      string :latest_mail_state, choices: { values: { 'pending' => 'Not yet queued', 'queued' => 'Queued for sending', 'sent' => 'Accepted by mail server', 'failed' => 'Sending failed', 'uncertain' => 'Sending outcome uncertain', 'suppressed' => 'Sending suppressed' } }, nullable: true, label: 'Latest email state', desc: 'Sent means acceptance by the mail server, without proof of inbox delivery.'
      datetime :latest_stop_completed_at, nullable: true, label: 'Latest confirmed shutdown', desc: 'Confirmed VPS shutdown, independent of warning completion or email delivery.'
    end

    class Index < HaveAPI::Action
      include VpsAdmin::API::IncidentPolicyReadAction

      desc 'List VPS and policy pairs with currently counted incident reports'

      input do
        resource VpsAdmin::API::Resources::VPS, value_label: :hostname
        resource VpsAdmin::API::Resources::User, value_label: :login
        resource VpsAdmin::API::Resources::Node, value_label: :domain_name
        string :policy_key, label: 'Policy key'
        string :status, choices: { values: { 'clear' => 'Below thresholds', 'near_limit' => 'Near a threshold', 'warning' => 'Warning threshold reached', 'stop_threshold' => 'Shutdown threshold reached', 'invalid' => 'Invalid configuration' } }, label: 'Threshold status'
        string :effective_mode, choices: { values: { 'observe' => 'Observation only', 'notify' => 'Warnings only', 'enforce' => 'Automatic shutdown permitted' } }, label: 'Effective mode'
        bool :stop_enforced, label: 'Automatic shutdown permitted'
        string :sort, choices: { values: { 'severity' => 'Priority', 'vps_id' => 'VPS ID', 'user_login' => 'Owner login', 'policy_key' => 'Policy key', 'count_7d' => '7-day incident count', 'count_30d' => '30-day incident count', 'warning_remaining' => 'Reports until warning threshold', 'stop_remaining' => 'Reports until shutdown threshold', 'last_incident_at' => 'Last counted incident' } }, default: 'severity', fill: true, label: 'Order by'
        string :direction, choices: { values: { 'asc' => 'Ascending', 'desc' => 'Descending' } }, label: 'Direction'
      end
      output(:object_list) { use :all }

      def exec
        options = input.except(:as_of, :vps, :user, :node).compact
        %i[vps user node].each { |key| options[:"#{key}_id"] = input[key].id if input[key] }
        result = read_projection.exposures(**options)
        set_meta(result[:meta])
        result[:rows].map do |row|
          references = { vps: reference(row[:vps_id], :hostname, row[:hostname]),
                         user: reference(row[:user_id], :login, row[:user_login]),
                         node: reference(row[:node_id], :domain_name, row[:node_name]) }
          row.except(:vps_id, :hostname, :user_id, :user_login, :node_id, :node_name).merge(references)
        end
      rescue ArgumentError => e
        error!(e.message)
      end

      protected

      def reference(id, label, value)
        { id:, label => value, _meta: { path_params: [id], resolved: false } }
      end
    end
  end
end
