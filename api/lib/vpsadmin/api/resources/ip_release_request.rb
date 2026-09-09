module VpsAdmin::API::Resources
  class IpReleaseRequest < HaveAPI::Resource
    model ::IpReleaseRequest
    desc 'Browse IP release requests'

    params(:all) do
      id :id, label: 'ID'
      resource IpReleaseCampaign, label: 'IP release campaign'
      resource User, value_label: :login, nullable: true
      integer :original_user_id, label: 'Original user ID'
      string :user_login, label: 'User login', nullable: true
      string :label, label: 'Label'
      datetime :deadline, label: 'Planned release date', desc: 'Advisory date for releasing unused IP addresses'
      bool :allow_keep, label: 'Allow user opt-outs', desc: 'Honor user reasons when deciding which IPs to release'
      datetime :closed_at, label: 'Closed at', nullable: true
      datetime :notified_at, label: 'Last notice queued', nullable: true
      resource MailLog, label: 'Last notice', value_label: :subject, nullable: true
    end

    def self.visible_to(user)
      user.role == :admin ? ::IpReleaseRequest.all : ::IpReleaseRequest.where(user_id: user.id)
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource IpReleaseCampaign, label: 'IP release campaign'
      end
      output(:object_list) { use :all }
      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i[user original_user_id user_login mail_log]
        allow
      end

      def query
        q = self.class.resource.visible_to(current_user)
        q = q.where(ip_release_campaign: input[:ip_release_campaign]) if input[:ip_release_campaign]
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query.includes(:ip_release_campaign).order(:id)))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output { use :all }
      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i[user original_user_id user_login mail_log]
        allow
      end

      def exec
        self.class.resource.visible_to(current_user).find(path_params['ip_release_request_id'])
      end
    end

    class Keep < HaveAPI::Action
      include IpReleaseCampaign::Errors

      desc 'Keep selected IP addresses with a reason'
      route '{%{resource}_id}/keep'
      http_method :post
      input do
        custom :addresses, label: 'IP addresses', required: true, desc: 'Array of request address IDs'
        text :reason, label: 'Reason', required: true
      end
      output { use :all, exclude: %i[user original_user_id user_login mail_log] }
      authorize { |_u| allow }

      def perform
        request = ::IpReleaseRequest.where(user_id: current_user.id).find(path_params['ip_release_request_id'])
        request.keep!(ids: input[:addresses], reason: input[:reason], actor: current_user)
        request
      end
    end

    class Notice < HaveAPI::Resource
      model ::IpReleaseRequestNotice
      desc 'Browse notices queued for this IP release request'
      route '{ip_release_request_id}/notices'

      class Index < HaveAPI::Actions::Default::Index
        output(:object_list) do
          id :id, label: 'ID'
          string :event, label: 'Notice type', choices: %w[requested reminder]
          string :subject, label: 'Subject'
          datetime :created_at, label: 'Queued at'
          resource User, name: :created_by, label: 'Queued by', value_label: :login, nullable: true
          string :created_by_login, label: 'Queued by login', nullable: true
          resource MailLog, label: 'Mail log', value_label: :subject
        end
        authorize do |u|
          allow if u.role == :admin
          output blacklist: %i[created_by created_by_login mail_log]
          allow
        end

        def query
          IpReleaseRequest.visible_to(current_user).find(path_params['ip_release_request_id'])
                          .ip_release_request_notices.includes(:mail_log, :created_by).order(:id)
        end

        def count
          query.count
        end

        def exec
          with_pagination(with_includes(query))
        end
      end
    end

    class Address < HaveAPI::Resource
      model ::IpReleaseRequestAddress
      desc 'Browse IP addresses in a release request'
      route '{ip_release_request_id}/addresses'

      params(:all) do
        id :id, label: 'ID'
        resource IpAddress, label: 'IP address', value_label: :addr, nullable: true
        string :address, label: 'IP address'
        integer :prefix, label: 'Prefix'
        integer :size, label: 'Allocation size'
        string :protection, label: 'Current status'
        text :keep_reason, label: 'User reason', nullable: true
        datetime :kept_at, label: 'Reason submitted at', nullable: true
        text :exemption_reason, label: 'Admin exemption reason', nullable: true
        datetime :exempted_at, label: 'Exempted at', nullable: true
        datetime :excluded_at, label: 'Excluded at', nullable: true
        string :exclusion_reason, label: 'Exclusion reason', nullable: true
        datetime :released_at, label: 'Released at', nullable: true
        string :cleanup_state, label: 'Cleanup state', nullable: true
        string :last_result, label: 'Last release result', nullable: true
        text :last_error, label: 'Last error', nullable: true
        resource TransactionChain, name: :release_chain, label: 'Release transaction chain', nullable: true
      end

      module Scope
        def release_request
          @release_request ||= IpReleaseRequest.visible_to(current_user).find(path_params['ip_release_request_id'])
        end
      end

      class Index < HaveAPI::Actions::Default::Index
        include Scope

        output(:object_list) { use :all }
        authorize do |u|
          allow if u.role == :admin
          output blacklist: %i[last_error release_chain]
          allow
        end

        def query
          release_request.ip_release_request_addresses.includes(:ip_address, :release_chain).order(:id)
        end

        def count
          query.count
        end

        def exec
          with_pagination(with_includes(query))
        end
      end

      class Exempt < HaveAPI::Action
        include Scope
        include IpReleaseCampaign::Errors

        desc 'Set an admin exemption with a reason, or remove it by passing a null reason'
        route '{%{resource}_id}/exempt'
        http_method :post
        input do
          text :reason, label: 'Reason', required: true, nullable: true
        end
        output { use :all }
        authorize { |u| allow if u.role == :admin }

        def perform
          item = release_request.ip_release_request_addresses.find(path_params['address_id'])
          item.exempt!(reason: input[:reason], actor: current_user)
          item
        end
      end
    end
  end
end
