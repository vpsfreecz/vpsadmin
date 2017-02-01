VpsAdmin::API::Plugin.register(:webui) do
  name 'Web UI support'
  description 'Support for Web UI specific API endpoints'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api
end
