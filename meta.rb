VpsAdmin::API::Plugin.register(:newslog) do
  name 'News log'
  description "Lets admins to announce news"
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api
end
