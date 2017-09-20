module VpsAdmin::API::Resources
  class MailLog < HaveAPI::Resource
    model ::MailLog
    desc 'Browse sent mails'

    params(:all) do
      id :id
      resource User, value_label: :login
      string :to
      string :cc
      string :bcc
      string :from
      string :reply_to
      string :return_path
      string :message_id
      string :in_reply_to
      string :references
      string :subject
      string :text_plain
      string :text_html
      resource MailTemplate
      #resource TransactionChain::Transaction
      datetime :created_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List mails'

      input do
        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::MailLog.all
      end

      def count
        query.count
      end

      def exec
        with_includes(query).offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'View mail'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @mail = ::MailLog.find(params[:mail_log_id])
      end

      def exec
        @mail
      end
    end
  end
end
