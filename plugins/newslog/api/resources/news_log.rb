module VpsAdmin::API::Resources
  class NewsLog < HaveAPI::Resource
    desc 'Browse and manage news'
    model ::NewsLog

    params(:messages) do
      ::Language.order(:id).each do |lang|
        text :"#{lang.code}_message", label: "#{lang.label} message"
      end
    end

    params(:editable) do
      use :messages
      datetime :published_at, label: 'Published at'
    end

    params(:all) do
      id :id
      text :message, label: 'Message', db_name: :localized_message
      use :editable
      datetime :created_at
      datetime :updated_at
    end

    module Helpers
      def extract_translations
        translations = {}

        ::Language.order(:id).each do |lang|
          name = :"#{lang.code}_message"
          next unless input.has_key?(name)

          translations[lang] = { message: input.delete(name) }
        end

        translations
      end

      def default_language
        @default_language ||= ::Language.find_by(code: ::NewsLog::DEFAULT_LANGUAGE_CODE)
      end

      def default_message(translations)
        lang = default_language
        return unless lang

        translations.each do |translation_lang, attrs|
          return attrs[:message] if translation_lang.id == lang.id
        end

        nil
      end
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

      authorize do |_u|
        allow
      end

      def query
        q = ::NewsLog.all
        q = q.where('published_at > ?', input[:since]) if input[:since]

        q = q.where('published_at <= ?', Time.now) if current_user.nil? || current_user.role != :admin

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order('published_at DESC')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show news'
      auth false

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        q = ::NewsLog.where(id: path_params['news_log_id'])
        q = q.where('published_at <= ?', Time.now) if current_user.nil? || current_user.role != :admin

        @news = q.take!
      end

      def exec
        @news
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Publish news'
      include Helpers

      input do
        use :editable
        patch :en_message, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        translations = extract_translations
        input[:published_at] ||= Time.now

        ::NewsLog.transaction do
          news = ::NewsLog.create!(
            input.merge(message: default_message(translations))
          )
          news.update_translations!(translations)
          news
        end
      rescue ActiveRecord::RecordInvalid => e
        error!('Create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update news'
      include Helpers

      input do
        use :editable
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        n = ::NewsLog.find(path_params['news_log_id'])
        translations = extract_translations

        n.update!(input)
        n.update_translations!(translations) if translations.any?
        n
      rescue ActiveRecord::RecordInvalid => e
        error!('Update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete news'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        n = ::NewsLog.find(path_params['news_log_id'])
        n.destroy!
        ok!
      end
    end
  end
end
