template :security_advisory_user_update do
  label 'Security advisory update'

  lang :en do
    subject 'Re: [vpsAdmin] Security advisory: <%= @a.cves %>'
  end

  lang :cs do
    subject 'Re: [vpsAdmin] Bezpečnostní oznámení: <%= @a.cves %>'
  end
end
