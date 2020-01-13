module VpsAdmin::API::Resources
  Location::Index.auth false
  Location::Index.authorize do |u|
    allow if u && u.role == :admin

    if u
      output whitelist: %i(id label environment remote_console_server)
    else
      output whitelist: %i(id label environment)
    end

    allow
  end

  OsTemplate::Index.auth false
  OsTemplate::Index.authorize do |u|
    allow if u && u.role == :admin

    if u
      restrict enabled: true
      output whitelist: %i(id name label info supported hypervisor_type)

    else
      restrict enabled: true, supported: true
      output whitelist: %i(id name label hypervisor_type)
    end

    allow
  end

  Language::Index.auth false
end
