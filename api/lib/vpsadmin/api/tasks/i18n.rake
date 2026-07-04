namespace :vpsadmin do
  namespace :i18n do
    desc 'Generate vpsAdmin API translation catalogs'
    task :update do
      require 'vpsadmin/api/i18n/catalog'

      VpsAdmin::API::I18n::Catalog.new(
        root: File.realpath(File.join(__dir__, '..', '..', '..', '..', '..'))
      ).update!
    end

    desc 'Check vpsAdmin API translation coverage and generated catalogs'
    task :health do
      require 'vpsadmin/api/i18n/catalog'

      VpsAdmin::API::I18n::Catalog.new(
        root: File.realpath(File.join(__dir__, '..', '..', '..', '..', '..'))
      ).check!
    end
  end
end
