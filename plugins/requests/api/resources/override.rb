module VpsAdmin::API::Resources
  Location::Index.auth false
  Location::Index.authorize do |u|
    allow if u && u.role == :admin

    if u
      output whitelist: Location::AUTHENTICATED_OUTPUT_PARAMS
    else
      output whitelist: Location::ANONYMOUS_OUTPUT_PARAMS
    end

    allow
  end

  Location::Show.auth false
  Location::Show.authorize do |u|
    allow if u && u.role == :admin

    if u
      output whitelist: Location::AUTHENTICATED_OUTPUT_PARAMS
    else
      output whitelist: Location::ANONYMOUS_OUTPUT_PARAMS
    end

    allow
  end

  OsTemplate::Index.auth false
  OsTemplate::Index.authorize do |u|
    allow if u && u.role == :admin

    if u
      restrict enabled: true
      output whitelist: %i[id name label info supported hypervisor_type cgroup_version
                           vendor variant arch distribution version os_family
                           enable_script enable_cloud_init]

    else
      restrict enabled: true, supported: true
      output whitelist: %i[id name label hypervisor_type]
    end

    allow
  end

  OsTemplate::Show.auth false
  OsTemplate::Show.authorize do |u|
    allow if u && u.role == :admin

    if u
      output whitelist: %i[id name label info supported hypervisor_type cgroup_version
                           vendor variant arch distribution version os_family
                           enable_script enable_cloud_init enabled]
    else
      restrict enabled: true, supported: true
      output whitelist: %i[id name label hypervisor_type]
    end

    allow
  end

  Language::Index.auth false
end
