module VpsAdmin::API::Resources
  class EmailRecipient < HaveAPI::Resource
    model ::EmailRecipient
    desc 'Manage email recipients'

    params(:common) do
      string :label, desc: 'Human-friendly label'
      string :to, nullable: true
      string :cc, nullable: true
      string :bcc, nullable: true
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List email recipients'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::EmailRecipient.all
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'View email recipient'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @r = ::EmailRecipient.find(path_params['email_recipient_id'])
      end

      def exec
        @r
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a email recipient'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        tpl = ::EmailRecipient.new(input)

        if tpl.save
          ok!(tpl)

        else
          error!('save failed', tpl.errors.to_hash)
        end
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a email recipient'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        tpl = ::EmailRecipient.find(path_params['email_recipient_id'])

        if tpl.update(input)
          ok!(tpl)

        else
          error!('update failed', tpl.errors.to_hash)
        end
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete a email recipient'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::EmailRecipient.find(path_params['email_recipient_id']).destroy!
        ok!
      end
    end
  end
end
