module VpsAdmin::API::Resources
  class IpReleaseCampaign < HaveAPI::Resource
    model ::IpReleaseCampaign
    desc 'Manage IP release campaigns'

    params(:editable) do
      datetime :deadline, label: 'Planned release date', desc: 'Advisory date for releasing unused IP addresses'
      bool :allow_keep, label: 'Allow user opt-outs', desc: 'Honor user reasons when deciding which IPs to release'
    end

    params(:all) do
      id :id, label: 'ID'
      use :editable
      datetime :created_at, label: 'Created at'
      datetime :closed_at, label: 'Closed at', nullable: true
      resource User, name: :created_by, label: 'Created by', value_label: :login
      resource User, name: :closed_by, label: 'Closed by', value_label: :login, nullable: true
    end

    params(:ip_counts) do
      integer :total_ip_count, label: 'Total IPs', desc: 'All allocations recorded in the campaign, including historical rows'
      integer :to_release_ip_count, label: 'IPs to be released', desc: 'Eligible allocations in an open campaign and releases in progress'
      integer :kept_ip_count, label: 'Kept IPs', desc: 'Allocations protected by assignment, service use, exemptions or reasons honored under the current policy'
    end

    params(:release_attempt) do
      id :id, label: 'ID'
      datetime :created_at, label: 'Created at'
      integer :created_by_id, label: 'Started by ID'
      string :created_by_login, label: 'Started by', nullable: true
      integer :ip_count, label: 'IP count'
      string :state, label: 'State'
      text :error, label: 'Preparation error', nullable: true
      string :blocked_resource, label: 'Busy resource', nullable: true
      integer :blocked_resource_id, label: 'Busy resource ID', nullable: true
      integer :blocked_chain_id, label: 'Blocking transaction chain ID', nullable: true
      resource TransactionChain, label: 'Transaction chain', nullable: true
    end

    module Errors
      MESSAGES = {
        'invalid_addresses' => VpsAdmin::API::I18n.message('errors.ip_release.invalid_addresses'),
        'invalid_filters' => VpsAdmin::API::I18n.message('errors.ip_release.invalid_filters'),
        'ineligible_addresses' => VpsAdmin::API::I18n.message('errors.ip_release.ineligible_addresses'),
        'duplicate_addresses' => VpsAdmin::API::I18n.message('errors.ip_release.duplicate_addresses'),
        'closed' => VpsAdmin::API::I18n.message('errors.ip_release.closed'),
        'access_denied' => VpsAdmin::API::I18n.message('errors.ip_release.access_denied'),
        'keep_disabled' => VpsAdmin::API::I18n.message('errors.ip_release.keep_disabled'),
        'already_released' => VpsAdmin::API::I18n.message('errors.ip_release.already_released'),
        'owner_changed' => VpsAdmin::API::I18n.message('errors.ip_release.owner_changed')
      }.freeze

      def exec
        perform
      rescue ::IpReleaseCampaign::Error => e
        error!(MESSAGES.fetch(e.message))
      rescue ActiveRecord::RecordInvalid => e
        error!(VpsAdmin::API::I18n.message('errors.ip_release.invalid_record'), e.record.errors.to_hash)
      end
    end

    module AddressParams
      MEMBER_FIELDS = %i[id assign_ip_address_id address location_label prefix size protection
                         keep_reason kept_at exemption_reason exempted_at].freeze

      def self.included(resource)
        resource.params(:all) do
          id :id, label: 'ID'
          resource IpAddress, label: 'IP address', value_label: :addr, nullable: true
          integer :assign_ip_address_id, label: 'Address available for assignment', nullable: true
          string :address, label: 'IP address'
          string :location_label, label: 'Location', nullable: true
          integer :original_user_id, label: 'Original user ID'
          string :user_login, label: 'User login', nullable: true
          integer :prefix, label: 'Prefix'
          integer :size, label: 'Allocation size'
          string :protection, label: 'Current status'
          text :keep_reason, label: 'User reason', nullable: true
          datetime :kept_at, label: 'Reason submitted at', nullable: true
          integer :kept_by_id, label: 'Reason author ID', nullable: true
          string :kept_by_login, label: 'Reason author', nullable: true
          text :exemption_reason, label: 'Admin exemption reason', nullable: true
          datetime :exempted_at, label: 'Exempted at', nullable: true
          integer :exempted_by_id, label: 'Exempted by ID', nullable: true
          string :exempted_by_login, label: 'Exempted by', nullable: true
          datetime :excluded_at, label: 'Excluded at', nullable: true
          string :exclusion_reason, label: 'Exclusion reason', nullable: true
          datetime :released_at, label: 'Released at', nullable: true
          string :cleanup_state, label: 'Cleanup state', nullable: true
          string :last_result, label: 'Last release result', nullable: true
          resource TransactionChain, name: :release_chain, label: 'Release transaction chain', nullable: true
        end
      end
    end

    module NoticeParams
      def self.included(resource)
        resource.params(:all) do
          id :id, label: 'ID'
          string :event, label: 'Notice type', choices: %w[requested reminder]
          string :subject, label: 'Subject'
          integer :original_user_id, label: 'Original user ID'
          string :user_login, label: 'User login', nullable: true
          datetime :created_at, label: 'Queued at'
          resource User, name: :created_by, label: 'Queued by', value_label: :login, nullable: true
          string :created_by_login, label: 'Queued by login', nullable: true
          resource MailLog, label: 'Mail log', value_label: :subject
        end
      end
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        bool :open, label: 'Open'
      end
      output(:object_list) do
        use :all
        use :ip_counts
      end
      authorize { |u| allow if u.role == :admin }

      def query
        q = ::IpReleaseCampaign.all
        q = input[:open] ? q.where(closed_at: nil) : q.where.not(closed_at: nil) if input.has_key?(:open)
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query.order(:id))).tap { |rows| rows.each(&:load_ip_counts) }
      end
    end

    class Candidates < HaveAPI::Actions::Default::Index
      model ::IpAddress
      include Errors

      desc 'Preview unassigned owned IP addresses for a release campaign'
      route 'candidates'
      aliases []
      http_method :get
      input do
        patch :limit, default: 500, fill: true
        string :versions, label: 'IP versions', default: '4', fill: true, desc: 'Comma-separated IP versions: 4, 6, or both'
        string :networks, label: 'Networks', default: '', fill: true, desc: 'Comma-separated network IDs; empty selects all networks'
        string :locations, label: 'Locations', default: '', fill: true, desc: 'Comma-separated location IDs; empty selects all locations'
        string :access, label: 'Access', choices: %w[public_access private_access all], default: 'public_access', fill: true
        resource User
      end
      output(:object_list) do
        id :id, label: 'ID'
        string :addr, label: 'IP address'
        integer :prefix, label: 'Prefix'
        integer :size, label: 'Allocation size'
        resource User, value_label: :login
        resource Network, value_label: :label
      end
      authorize { |u| allow if u.role == :admin }

      def query
        ::IpReleaseCampaign.candidates(input)
      end

      def count
        query.count
      end

      def perform
        with_pagination(query.includes(:user, :network).order(:id))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
        use :ip_counts
        bool :can_send_initial_notices, label: 'Can send initial notices'
        bool :can_send_reminders, label: 'Can send reminders'
        bool :can_release, label: 'Can release'
        resource Attempt, name: :latest_release_attempt, label: 'Latest release attempt', value_label: :id, nullable: true
      end
      authorize { |u| allow if u.role == :admin }

      def exec
        ::IpReleaseCampaign.find(path_params['ip_release_campaign_id']).load_ip_counts
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include Errors

      input do
        use :editable
        patch :allow_keep, default: true, fill: true
        custom :addresses, label: 'IP addresses', required: true, desc: 'Array of IP address IDs from the preview'
      end
      output { use :all }
      authorize { |u| allow if u.role == :admin }

      def perform
        ::IpReleaseCampaign.create_selected!(
          ids: input[:addresses], actor: current_user,
          deadline: input[:deadline] || (Time.now + (7 * 24 * 60 * 60)), allow_keep: input[:allow_keep]
        )
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include Errors

      input { use :editable }
      output { use :all }
      authorize { |u| allow if u.role == :admin }

      def perform
        campaign = ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
        campaign.edit!(input.to_h, actor: current_user)
        campaign
      end
    end

    class Close < HaveAPI::Action
      include Errors

      desc 'Close an IP release campaign'
      route '{%{resource}_id}/close'
      http_method :post
      output { use :all }
      authorize { |u| allow if u.role == :admin }

      def perform
        campaign = ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
        campaign.close!(actor: current_user)
        campaign
      end
    end

    class Notify < HaveAPI::Action
      include Errors

      desc 'Send IP release notices'
      route '{%{resource}_id}/notify'
      http_method :post
      blocking true
      input do
        string :event, label: 'Notice type', choices: %w[requested reminder], default: 'requested', fill: true
      end
      output { use :all }
      authorize { |u| allow if u.role == :admin }

      def perform
        campaign = ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
        @chain, = campaign.notify!(event: input[:event], actor: current_user)
        campaign
      end

      def state_id
        @chain&.id
      end
    end

    class Attempt < HaveAPI::Resource
      model ::IpReleaseAttempt
      desc 'Inspect campaign release attempts'
      route '{ip_release_campaign_id}/attempts'
      params(:release_attempt, &IpReleaseCampaign.params(:release_attempt))

      class Index < HaveAPI::Actions::Default::Index
        output(:object_list) { use :release_attempt }
        authorize { |u| allow if u.role == :admin }

        def query
          ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
                             .ip_release_attempts.includes(:transaction_chain, :created_by).order(:id)
        end

        def count
          query.count
        end

        def exec
          with_pagination(with_includes(query))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        resolve ->(attempt) { [attempt.ip_release_campaign_id, attempt.id] }
        output { use :release_attempt }
        authorize { |u| allow if u.role == :admin }

        def exec
          ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
                             .ip_release_attempts.find(path_params['attempt_id'])
        end
      end
    end

    class Release < HaveAPI::Action
      include Errors

      desc 'Release all eligible IP addresses in this campaign now'
      route '{%{resource}_id}/release'
      http_method :post
      blocking true
      output { use :release_attempt }
      authorize { |u| allow if u.role == :admin }

      def perform
        @attempt = ::IpReleaseCampaign.find(path_params['ip_release_campaign_id']).release!(actor: current_user)
      end

      def state_id
        # ActionState belongs to its initiating user. Other administrators can
        # inspect the shared chain through the attempt resource.
        @attempt.transaction_chain_id if @attempt&.created_by_id == current_user.id
      end
    end

    class Address < HaveAPI::Resource
      model ::IpReleaseRequestAddress
      desc 'Browse all addresses in a release campaign'
      route '{ip_release_campaign_id}/addresses'
      include AddressParams

      class Index < HaveAPI::Actions::Default::Index
        input do
          patch :limit, default: 500, fill: true
        end
        output(:object_list) { use :all }
        authorize { |u| allow if u.role == :admin }

        def query
          ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
                             .ip_release_request_addresses
                             .includes(:ip_release_request, :ip_address, :release_chain, :kept_by, :exempted_by).order(:id)
        end

        def count
          query.count
        end

        def exec
          with_pagination(with_includes(query))
        end
      end
    end

    class Notice < HaveAPI::Resource
      model ::IpReleaseRequestNotice
      desc 'Browse notices queued for all users in a release campaign'
      route '{ip_release_campaign_id}/notices'
      include NoticeParams

      class Index < HaveAPI::Actions::Default::Index
        output(:object_list) { use :all }
        authorize { |u| allow if u.role == :admin }

        def query
          campaign = ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
          ::IpReleaseRequestNotice.where(ip_release_request_id: campaign.ip_release_requests.select(:id))
                                  .includes(:ip_release_request, :mail_log, :created_by).order(:id)
        end

        def count
          query.count
        end

        def exec
          with_pagination(with_includes(query))
        end
      end
    end

    class Exempt < HaveAPI::Action
      include Errors

      desc 'Set or remove an administrator exemption for selected campaign addresses'
      route '{%{resource}_id}/exempt'
      http_method :post
      input do
        custom :addresses, label: 'IP addresses', required: true, desc: 'Array of request address IDs'
        text :reason, label: 'Reason'
        bool :remove, label: 'Remove exemption', default: false, fill: true
      end
      output { use :all }
      authorize { |u| allow if u.role == :admin }

      def perform
        campaign = ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
        campaign.exempt!(ids: input[:addresses], reason: input[:remove] ? nil : input[:reason].to_s, actor: current_user)
        campaign
      end
    end
  end
end
