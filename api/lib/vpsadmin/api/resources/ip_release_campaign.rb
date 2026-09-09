module VpsAdmin::API::Resources
  class IpReleaseCampaign < HaveAPI::Resource
    model ::IpReleaseCampaign
    desc 'Manage IP release campaigns'

    params(:editable) do
      string :label, label: 'Label'
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

    module Errors
      MESSAGES = {
        'invalid_addresses' => VpsAdmin::API::I18n.message('errors.ip_release.invalid_addresses'),
        'too_many_addresses' => VpsAdmin::API::I18n.message('errors.ip_release.too_many_addresses'),
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

    class Index < HaveAPI::Actions::Default::Index
      input do
        bool :open, label: 'Open'
      end
      output(:object_list) { use :all }
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
        with_pagination(with_includes(query.order(:id)))
      end
    end

    class Candidates < HaveAPI::Actions::Default::Index
      model ::IpAddress
      desc 'Preview unassigned owned IP addresses for a release campaign'
      route 'candidates'
      aliases []
      http_method :get
      input do
        patch :limit, default: ::IpReleaseCampaign::MAX_ADDRESSES, fill: true, number: { min: 1, max: ::IpReleaseCampaign::MAX_ADDRESSES }
        integer :version, label: 'IP version', choices: [4, 6], default: 4, fill: true
        resource User
        resource Network
        resource Location
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

      def exec
        with_pagination(query.includes(:user, :network).order(:id))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output { use :all }
      authorize { |u| allow if u.role == :admin }

      def exec
        ::IpReleaseCampaign.find(path_params['ip_release_campaign_id'])
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include Errors

      input do
        use :editable
        patch :label, required: true
        patch :allow_keep, default: true, fill: true
        custom :addresses, label: 'IP addresses', required: true, desc: "Array of up to #{::IpReleaseCampaign::MAX_ADDRESSES} IP address IDs from the preview"
      end
      output { use :all }
      authorize { |u| allow if u.role == :admin }

      def perform
        ::IpReleaseCampaign.create_selected!(
          ids: input[:addresses], actor: current_user, label: input[:label],
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

    class Release < HaveAPI::Action
      include Errors

      desc 'Release all eligible IP addresses in this campaign now'
      route '{%{resource}_id}/release'
      http_method :post
      output(:object_list) do
        id :id, label: 'ID'
        string :address, label: 'IP address'
        string :last_result, label: 'Last release result'
        string :last_error, label: 'Last error', nullable: true
        datetime :excluded_at, label: 'Excluded at', nullable: true
        string :exclusion_reason, label: 'Exclusion reason', nullable: true
        datetime :released_at, label: 'Released at', nullable: true
        resource TransactionChain, name: :release_chain, label: 'Release transaction chain', nullable: true
        string :cleanup_state, label: 'Cleanup state', nullable: true
      end
      authorize { |u| allow if u.role == :admin }

      def perform
        ::IpReleaseCampaign.find(path_params['ip_release_campaign_id']).release!(actor: current_user)
      end
    end
  end
end
