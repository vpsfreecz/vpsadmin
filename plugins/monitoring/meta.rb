VpsAdmin::API::Plugin.register(:monitoring) do
  name 'Monitoring'
  description 'Monitors resource usage and sends alerts'
  version '3.0.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api
end
