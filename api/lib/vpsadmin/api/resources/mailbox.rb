module VpsAdmin::API::Resources
  class Mailbox < HaveAPI::Resource
    model ::Mailbox
    desc 'Manage mailboxes'

    params(:id) do
      integer :id, label: 'ID'
    end

    params(:common) do
      string :label
      string :server
      integer :port
      string :user
      string :password
      bool :enable_ssl, default: true, fill: true
    end

    params(:all) do
      use :id
      use :common, exclude: %i[password]
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List mailboxes'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::Mailbox.all
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show mailbox'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @mailbox = ::Mailbox.find(params[:mailbox_id])
      end

      def exec
        @mailbox
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a mailbox'

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
        ::Mailbox.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update mailbox'

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
        ::Mailbox.find(params[:mailbox_id]).update!(input)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete mailbox'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::Mailbox.find(params[:mailbox_id]).destroy!
        ok
      end
    end

    class Handler < HaveAPI::Resource
      route '{mailbox_id}/handler'
      model ::MailboxHandler
      desc 'Manage mailbox handlers'

      params(:common) do
        string :class_name
        integer :order
        bool :continue
      end

      params(:all) do
        id :id
        use :common
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List mailbox handlers'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def query
          ::MailboxHandler.joins(:mailbox).where(
            mailboxes: { id: params[:mailbox_id] }
          )
        end

        def count
          query.count
        end

        def exec
          query.order('order').limit(input[:limit]).offset(input[:offset])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show mailbox handler'
        resolve ->(handler) { [handler.mailbox_id, handler.id] }

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @handler = ::MailboxHandler.joins(:mailbox).find_by!(
            mailboxes: { id: params[:mailbox_id] },
            id: params[:handler_id]
          )
        end

        def exec
          @handler
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Add mailbox handler'

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
          ::MailboxHandler.create!(input.merge(
                                     mailbox: ::Mailbox.find(params[:mailbox_id])
                                   ))
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update mailbox handler'

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
          ::MailboxHandler.joins(:mailbox).find_by!(
            mailboxes: { id: params[:mailbox_id] },
            id: params[:handler_id]
          ).update!(input)
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete mailbox handler'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          ::MailboxHandler.joins(:mailbox).find_by!(
            mailboxes: { id: params[:mailbox_id] },
            id: params[:handler_id]
          ).destroy!
          ok
        end
      end
    end
  end
end
