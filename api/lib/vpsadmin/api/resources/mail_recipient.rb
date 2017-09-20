module VpsAdmin::API::Resources
  class MailRecipient < HaveAPI::Resource
    model ::MailRecipient
    desc 'Manage mail recipients'

    params(:common) do
      string :label, desc: 'Human-friendly label'
      string :to
      string :cc
      string :bcc
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List mail recipients'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::MailRecipient.all
      end

      def count
        query.count
      end

      def exec
        with_includes(query).offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'View mail recipient'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @r = ::MailRecipient.find(params[:mail_recipient_id])
      end

      def exec
        @r
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a mail recipient'

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
        tpl = ::MailRecipient.new(input)

        if tpl.save
          ok(tpl)

        else
          error('save failed', tpl.errors.to_hash)
        end
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a mail recipient'

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
        tpl = ::MailRecipient.find(params[:mail_recipient_id])

        if tpl.update(input)
          ok(tpl)

        else
          error('update failed', tpl.errors.to_hash)
        end
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete a mail recipient'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::MailTemplate.find(params[:mail_recipient_id]).destroy
        ok
      end
    end
  end
end
