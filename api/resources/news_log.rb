module VpsAdmin::API::Resources
  class NewsLog < HaveAPI::Resource
    desc 'Browse and manage news'
    model ::NewsLog

    params(:editable) do
      text :message, label: 'Message'
      datetime :published_at, label: 'Published at'
    end

    params(:all) do
      id :id
      use :editable
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List news'
      auth false

      input do
        datetime :since, label: 'Since',
            desc: 'List news published later than this date'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow
      end

      def query
        q = ::NewsLog.all
        q = q.where('published_at > ?', input[:since]) if input[:since]

        if current_user.nil? || current_user.role != :admin
          q = q.where('published_at <= ?', Time.now)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
            .limit(input[:limit])
            .offset(input[:offset])
            .order('published_at DESC')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show news'
      auth false

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def prepare
        @news = ::NewsLog.find(params[:news_log_id])
      end

      def exec
        @news
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Publish news'

      input do
        use :editable
        patch :message, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        input[:published_at] ||= Time.now
        ::NewsLog.create!(input)

      rescue ActiveRecord::RecordInvalid => e
        error('Create failed', e.record.errors.to_hash)
      end
    end
    
    class Update < HaveAPI::Actions::Default::Update
      desc 'Update news'

      input do
        use :editable
        patch :message, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        n = ::NewsLog.find(params[:news_log_id])
        n.update!(input)
        n

      rescue ActiveRecord::RecordInvalid => e
        error('Update failed', e.record.errors.to_hash)
      end
    end
    
    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete news'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        n = ::NewsLog.find(params[:news_log_id])
        n.destroy!
        ok
      end
    end
  end
end
