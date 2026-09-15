module VpsAdmin::API::Resources
  class IpReleaseRequest < HaveAPI::Resource
    model ::IpReleaseRequest
    desc 'Browse IP release requests'

    params(:all) do
      id :id, label: 'ID'
      resource IpReleaseCampaign, label: 'IP release campaign', value_label: :id
      resource User, value_label: :login, nullable: true
      integer :original_user_id, label: 'Original user ID'
      string :user_login, label: 'User login', nullable: true
      datetime :deadline, label: 'Planned release date', desc: 'Advisory date for releasing unused IP addresses'
      bool :can_keep, label: 'Can keep addresses'
      bool :can_assign, label: 'Can assign addresses'
      bool :allow_keep, label: 'Allow user opt-outs', desc: 'Honor user reasons when deciding which IPs to release'
      datetime :closed_at, label: 'Closed at', nullable: true
      datetime :notified_at, label: 'Last notice queued', nullable: true
      resource MailLog, label: 'Last notice', value_label: :subject, nullable: true
    end

    MEMBER_FIELDS = %i[id deadline can_keep can_assign].freeze

    def self.visible_to(user)
      user.role == :admin ? ::IpReleaseRequest.all : ::IpReleaseRequest.where(user_id: user.id)
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        resource IpReleaseCampaign, label: 'IP release campaign', value_label: :id
      end
      output(:object_list) { use :all }
      authorize do |u|
        allow if u.role == :admin
        input blacklist: [:ip_release_campaign]
        output whitelist: IpReleaseRequest::MEMBER_FIELDS
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
        output whitelist: IpReleaseRequest::MEMBER_FIELDS
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
      output { use :all, include: IpReleaseRequest::MEMBER_FIELDS }
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
      include IpReleaseCampaign::NoticeParams

      class Index < HaveAPI::Actions::Default::Index
        output(:object_list) { use :all }
        authorize { |u| allow if u.role == :admin }

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

      include IpReleaseCampaign::AddressParams

      module Scope
        def release_request
          @release_request ||= IpReleaseRequest.visible_to(current_user).find(path_params['ip_release_request_id'])
        end
      end

      class Index < HaveAPI::Actions::Default::Index
        include Scope

        input { patch :limit, default: 500, fill: true }

        output(:object_list) { use :all }
        authorize do |u|
          allow if u.role == :admin
          output whitelist: IpReleaseCampaign::AddressParams::MEMBER_FIELDS
          allow
        end

        def query
          release_request.ip_release_request_addresses.includes(:ip_address, :release_chain, :kept_by, :exempted_by).order(:id)
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
