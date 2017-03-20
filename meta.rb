VpsAdmin::API::Plugin.register(:webui) do
  name 'Web UI support'
  description 'Support for Web UI specific API endpoints'
  version '2.7.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :webui, :base_url, String, min_user_level: 0
    SysConfig.register :webui, :document_title, String, min_user_level: 0
    SysConfig.register :webui, :noticeboard, Text, min_user_level: 0
    SysConfig.register :webui, :index_info_box_title, String, min_user_level: 0
    SysConfig.register :webui, :index_info_box_content, Text, min_user_level: 0

    MailTemplate.register :daily_report, vars: {
        base_url: [String, 'URL to the web UI'],
    }
  end
end
