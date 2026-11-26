VpsAdmin::API::Plugin.register(:webui) do
  name 'Web UI support'
  description 'Support for Web UI specific API endpoints'
  version '4.2.1'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :webui, :base_url, String, min_user_level: 0,
                                                  label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.base_url', default: 'Web UI URL')
    SysConfig.register :webui, :document_title, String, min_user_level: 0,
                                                        label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.document_title', default: 'Web UI page title')
    SysConfig.register :webui, :noticeboard, Hash,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.noticeboard', default: 'Noticeboard'),
                       min_user_level: 0,
                       localized: true
    SysConfig.register :webui, :index_info_box_title, Hash,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.index_info_box_title', default: 'Home page information box title'),
                       min_user_level: 0,
                       localized: true
    SysConfig.register :webui, :index_info_box_content, Hash,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.index_info_box_content', default: 'Home page information box content'),
                       min_user_level: 0,
                       localized: true
    SysConfig.register :webui, :sidebar, Hash,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.sidebar', default: 'Sidebar content'),
                       min_user_level: 0,
                       localized: true
    SysConfig.register :webui, :munin_url, String, min_user_level: 0,
                                                   label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.munin_url', default: 'Munin URL')
    SysConfig.register :webui, :goresheat_url, String, min_user_level: 0,
                                                       label: VpsAdmin::API::I18n.message('sysconfig.labels.webui.goresheat_url', default: 'Goresheat URL')

    MailTemplate.register :daily_report, vars: {
      base_url: [String, 'URL to the web UI']
    }
  end
end
