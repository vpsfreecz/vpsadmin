template :security_advisory_user_announce do
  label 'Security advisory announcement'

  lang :en do
    subject '[vpsAdmin] Security advisory: <%= @a.cves %>'
  end

  lang :cs do
    subject '[vpsAdmin] Bezpečnostní oznámení: <%= @a.cves %>'
  end
end
