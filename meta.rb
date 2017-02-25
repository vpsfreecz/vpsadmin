VpsAdmin::API::Plugin.register(:outage_reports) do
  name 'Outage reports'
  description 'Adds support for outage reporting and mailing affected users'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api
end
