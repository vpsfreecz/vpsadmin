template :vps_replaced do
  label 'VPS replaced'

  lang :en do
    subject '[vpsAdmin] VPS <%= @original_vps.hostname %> has been replaced'
  end
end
