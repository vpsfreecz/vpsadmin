VpsAdmin::API::Plugin.register(:newslog) do
  name 'News log'
  description "Lets admins to announce news"
  version '3.0.0.dev'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api
end
