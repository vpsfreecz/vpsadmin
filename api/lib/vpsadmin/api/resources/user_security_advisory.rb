module VpsAdmin::API::Resources
  class UserSecurityAdvisory < HaveAPI::Resource
    desc 'Browse users affected by security advisories'
    model ::SecurityAdvisoryUser

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::SecurityAdvisory, value_label: :id
      resource VpsAdmin::API::Resources::User, value_label: :login
      integer :vps_count
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List users affected by security advisory'

      input do
        use :all, include: %i[security_advisory user]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        output blacklist: %i[user]
        input blacklist: %i[user]
        allow
      end

      def query
        q = ::SecurityAdvisoryUser
            .joins(:security_advisory)
            .merge(::SecurityAdvisory.visible_to(current_user))
            .where(with_restricted)

        %i[security_advisory user].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order('security_advisory_users.id')
      end
    end
  end
end
