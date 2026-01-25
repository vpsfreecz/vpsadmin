let
  adminUser = {
    id = 1;
    login = "test-admin";
    password = "testAdminPassword";
    full_name = "Test Admin";
    email = "test-admin@example.test";
  };

  transactionKey = {
    private = ''
      -----BEGIN PRIVATE KEY-----
      MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDsZWGBaDtZh1ec
      XabGfQ1Eg5YuFIrf0TXGmOI9UIYrhtgEhmArYSzPcm4YDCfwqSy+78phMAV7EY/1
      BnchTi+rv02rOaX0NC9kvUYfmh11lOLGuunDsgeg5i0qTEKHe6jCxZLsmv/G5UIN
      0Rq3UayP2JpHOqDGX9ioPHaEwPtlINlacBn7OqeuzINo8AxjF3WjmkT7COysxk0O
      j2gIt0XyvoDTlSw4f/hrdhWJv7fmLHxMveaFqoBOktTl9AwmUbo0RszBuYnLLuUT
      tk3Wt3XA5DUCOVTcZqHgwAjVqJb3EZXXmdpiqh6RFIWLzKLgpylGAb6+jtnayg5E
      QZUFy3ZfAgMBAAECggEACoLPfROHYAm2iYtYeQbiaiN3sADV0/HXdEcj+Bn2fUT3
      oevfps4hUfACmSshM4AyLyM2Wm/qLnivb/OjpGV3lSliaLSdfmg7mz0XOxx9JtdB
      5hg1gLAPysWxSGovoxqKfG6Qg9i4er2C3F5p07Db/WFiKryenXNxjLlzg5+ZDfv8
      CtC3++fTSfgsSSD9vNQi4+0AMeCgNve2BgxALgmLMVJHc5H4tWFhzpg/uKpud+3C
      5ioa8ag2qyS3NlADgiXE5O4wPXlDk9mU7LVbzOiSKjUyWpx21EbcwA2W58LimJYM
      izePI5T4jP967Zp+8x9FjT0WXlJn359SibgQyRufEQKBgQD+BoIUy2E4wLRWz5Db
      Js9u4TE6aJf73V+qSLsZE+Okg2KRhldgd2o08su7ED8WJf7mrQs95oAeHr4ANcV/
      bpnlUK/Uc/jk6Oyw9lib8quR6BoxMIzzN7MWp5TydEFt4GdbJpnttVz4rauDjssZ
      WC1+rLwkjtttdayc28NC+qqVswKBgQDuO8qiNgQGOpKd/TwmtYcg7wxvWUPz1TSm
      Id+1irnerfS6mpoECUqLxn9HPhnr3a0SjjcKr2d/7+3s2E9sBcs+P+omix3ZrDc9
      7bm4BFfgFrFd+MiLC1bbnXcVNSTjjnAl2OAXRc1mX844L3vHPRQ57Y2s3OBi547B
      9u+a23oepQKBgA8W6eE8V5EceVnyyIMMIiRPAjKbBfQzKTyfR2Xs9YfPOiq01Tno
      vglZJtr80xKIvUSMoO9TYubnIpg2mX3BXyjtCxTOssk+QNkeORNCbgijxfKIFMdZ
      1qyQ1ds1JrHVM66Jc3lYXaZ0Ao01DUF7KHCu6Bov1j8BT3id4VJ4O2vbAoGBALCL
      wMvbCbpv9617N/NbvSsr2+Q8m73790tSeQ15I+sgsOcEoTRyijrxO+tY2y7PFW5V
      0/ZoLGREMua9GoZr+MVF6kjr+ZARLtMG9AWpulGHn6OLNVrNaW3Q0Kn3u0GjkfqK
      MO8uPFwsjY9XqPvqiK2xHLfI68R/42xcig4Rrfs9AoGBAPCTKHuXgPjg9wp9kVCD
      GoqSOtwqiHu4c8XZlDjppCm5SEu+bVMRBgj3hATVXDdguND9RevDD32WiHJmBbhh
      ShbLQBRZuHf+2elHY7KxbbExa4aawcHjE15HalTgW8zA1FsiSA1jESwVaW/PEcHJ
      9tUGBth7TYFaq0mqYAsYDYa/
      -----END PRIVATE KEY-----
    '';

    public = ''
      -----BEGIN PUBLIC KEY-----
      MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7GVhgWg7WYdXnF2mxn0N
      RIOWLhSK39E1xpjiPVCGK4bYBIZgK2Esz3JuGAwn8Kksvu/KYTAFexGP9QZ3IU4v
      q79Nqzml9DQvZL1GH5oddZTixrrpw7IHoOYtKkxCh3uowsWS7Jr/xuVCDdEat1Gs
      j9iaRzqgxl/YqDx2hMD7ZSDZWnAZ+zqnrsyDaPAMYxd1o5pE+wjsrMZNDo9oCLdF
      8r6A05UsOH/4a3YVib+35ix8TL3mhaqATpLU5fQMJlG6NEbMwbmJyy7lE7ZN1rd1
      wOQ1AjlU3Gah4MAI1aiW9xGV15naYqoekRSFi8yi4KcpRgG+vo7Z2soOREGVBct2
      XwIDAQAB
      -----END PUBLIC KEY-----
    '';
  };

  environment = {
    id = 1;
    label = "test";
    domain = "vpsadmin.test";
    maintenance_lock = 0;
    can_create_vps = false;
    can_destroy_vps = false;
    vps_lifetime = 0;
    max_vps_count = 1;
    user_ip_ownership = false;
  };

  location = {
    id = 1;
    label = "test-location";
    domain = "lab";
    description = "Test location for node registration";
    environment_id = environment.id;
    remote_console_server = "http://console.vpsadmin.test";
    has_ipv6 = false;
  };

  godlikeValues = {
    memory = 1024 * 1024; # MiB
    swap = 1024 * 1024; # MiB
    cpu = 8192;
    diskspace = 20 * 1024 * 1024; # MiB
    ipv4 = 256;
    ipv4_private = 256;
  };

  clusterResources = [
    {
      id = 1;
      name = "memory";
      label = "Memory";
      min = 1024;
      max = 128 * 1024;
      stepsize = 1;
      resource_type = "numeric";
    }
    {
      id = 2;
      name = "swap";
      label = "Swap";
      min = 0;
      max = 64 * 1024;
      stepsize = 1;
      resource_type = "numeric";
    }
    {
      id = 3;
      name = "cpu";
      label = "CPU";
      min = 1;
      max = 64;
      stepsize = 1;
      resource_type = "numeric";
    }
    {
      id = 4;
      name = "diskspace";
      label = "Disk space";
      min = 10 * 1024;
      max = 10 * 1024 * 1024;
      stepsize = 1;
      resource_type = "numeric";
    }
    {
      id = 5;
      name = "ipv4";
      label = "IPv4 address";
      min = 0;
      max = 64;
      stepsize = 1;
      resource_type = "object";
      free_chain = "Ip::Free";
    }
    {
      id = 6;
      name = "ipv4_private";
      label = "Private IPv4 address";
      min = 0;
      max = 1024;
      stepsize = 1;
      resource_type = "object";
      free_chain = "Ip::Free";
    }
  ];

  osFamilies = {
    debian = {
      id = 1;
      label = "Debian";
      description = "";
    };
    ubuntu = {
      id = 2;
      label = "Ubuntu";
      description = "";
    };
    alpine = {
      id = 3;
      label = "Alpine";
      description = "";
    };
    fedora = {
      id = 4;
      label = "Fedora";
      description = "";
    };
  };

  osTemplates =
    let
      mkTpl = id: family: label: distribution: rec {
        inherit id label distribution;
        os_family_id = family;
        hypervisor_type = 1; # vpsadminos
        cgroup_version = 0; # cgroup_any
        vendor = "vpsadminos";
        variant = "minimal";
        arch = "x86_64";
        version = "latest";
        name = "${distribution}-${version}-${arch}-${vendor}-${variant}";
        manage_hostname = true;
        manage_dns_resolver = true;
        enable_script = true;
        enable_cloud_init = true;
        config = { };
      };

      templates = [
        (mkTpl 1 osFamilies.debian.id "Debian (latest)" "debian")
        (mkTpl 2 osFamilies.ubuntu.id "Ubuntu (latest)" "ubuntu")
        (mkTpl 3 osFamilies.alpine.id "Alpine (latest)" "alpine")
        (mkTpl 4 osFamilies.fedora.id "Fedora (latest)" "fedora")
      ];
    in
    templates;

  dnsResolver = {
    id = 1;
    addrs = "8.8.8.8";
    label = "Test resolver";
    is_universal = true;
    location_id = null;
    ip_version = 4;
  };

  userNamespaceBlockSize = 65536;
  userNamespaceBlockCount = 1024;
  userNamespaceBlocksOwned = 8;

  userNamespace = {
    id = 1;
    user_id = adminUser.id;
    block_count = userNamespaceBlocksOwned;
    offset = 131072;
    size = userNamespaceBlockSize * userNamespaceBlocksOwned;
  };

  userNamespaceBlocks = builtins.genList (
    i:
    let
      idx = i + 1;
      offset = 131072 + i * userNamespaceBlockSize;
      owner = if idx <= userNamespaceBlocksOwned then userNamespace.id else null;
    in
    {
      id = idx;
      user_namespace_id = owner;
      index = idx;
      inherit offset;
      size = userNamespaceBlockSize;
    }
  ) userNamespaceBlockCount;

  userNamespaceMap = {
    id = 1;
    user_namespace_id = userNamespace.id;
    label = "Default map";
  };

  userNamespaceMapEntries = [
    {
      id = 1;
      user_namespace_map_id = userNamespaceMap.id;
      kind = 0; # uid
      vps_id = 0;
      ns_id = 0;
      count = userNamespace.size;
    }
    {
      id = 2;
      user_namespace_map_id = userNamespaceMap.id;
      kind = 1; # gid
      vps_id = 0;
      ns_id = 0;
      count = userNamespace.size;
    }
  ];

  environmentUserConfig = {
    environment_id = environment.id;
    user_id = adminUser.id;
    can_create_vps = true;
    can_destroy_vps = true;
    vps_lifetime = environment.vps_lifetime;
    max_vps_count = environment.max_vps_count;
    default = true;
  };

  personalPackage = {
    id = 1;
    label = "Personal package";
    environment_id = environment.id;
    user_id = adminUser.id;
  };

  godlikePackage = {
    id = 2;
    label = "Godlike";
    environment_id = null;
    user_id = null;
  };

  mkPackageItem = pkg: resource: value: {
    cluster_resource_package_id = pkg.id;
    cluster_resource_id = resource.id;
    inherit value;
  };

  personalPackageItems = map (r: mkPackageItem personalPackage r 0) clusterResources;

  godlikePackageItems = map (
    r: mkPackageItem godlikePackage r (builtins.getAttr r.name godlikeValues)
  ) clusterResources;

  userPackageLinks = [
    {
      environment_id = environment.id;
      user_id = adminUser.id;
      cluster_resource_package_id = personalPackage.id;
      added_by_id = adminUser.id;
      comment = "";
    }
    {
      environment_id = environment.id;
      user_id = adminUser.id;
      cluster_resource_package_id = godlikePackage.id;
      added_by_id = adminUser.id;
      comment = "";
    }
  ];

  userClusterResources = map (r: {
    user_id = adminUser.id;
    environment_id = environment.id;
    cluster_resource_id = r.id;
    value = builtins.getAttr r.name godlikeValues;
  }) clusterResources;

in
{
  inherit
    adminUser
    transactionKey
    environment
    location
    ;

  seed = [
    {
      model = "SysConfig";
      records = [
        {
          category = "core";
          name = "api_url";
          value = "http://api.vpsadmin.test";
          min_user_level = 0;
          data_type = "String";
        }
        {
          category = "core";
          name = "auth_url";
          value = "http://api.vpsadmin.test";
          min_user_level = 0;
          data_type = "String";
        }
        {
          category = "core";
          name = "support_mail";
          value = "support@example.invalid";
          min_user_level = 0;
          data_type = "String";
        }
        {
          category = "core";
          name = "logo_url";
          value = "http://webui.vpsadmin.test/logo.png";
          min_user_level = 0;
          data_type = "String";
        }
        {
          category = "core";
          name = "webauthn_rp_name";
          value = "vpsAdmin";
          min_user_level = 99;
          data_type = "String";
        }
        {
          category = "core";
          name = "transaction_key";
          value = transactionKey.private;
          min_user_level = 99;
          data_type = "String";
        }
        {
          category = "plugin_payments";
          name = "fio_api_tokens";
          value = [ ];
          min_user_level = 99;
          data_type = "String";
        }
      ];
    }
    {
      model = "ClusterResource";
      records = clusterResources;
    }
    {
      model = "Environment";
      records = [ environment ];
    }
    {
      model = "Location";
      records = [ location ];
    }
    {
      model = "User";
      records = [
        {
          id = adminUser.id;
          inherit (adminUser)
            login
            full_name
            email
            password
            ;
          level = 99;
          language = "en";
          enable_basic_auth = true;
          enable_token_auth = true;
          password_reset = false;
          lockout = false;
          object_state = "active";
        }
      ];
    }
    {
      model = "DnsResolver";
      records = [ dnsResolver ];
    }
    {
      model = "UserNamespace";
      records = [ userNamespace ];
    }
    {
      model = "UserNamespaceBlock";
      records = userNamespaceBlocks;
    }
    {
      model = "UserNamespaceMap";
      records = [ userNamespaceMap ];
    }
    {
      model = "UserNamespaceMapEntry";
      records = userNamespaceMapEntries;
    }
    {
      model = "EnvironmentUserConfig";
      records = [ environmentUserConfig ];
    }
    {
      model = "OsFamily";
      records = builtins.attrValues osFamilies;
    }
    {
      model = "OsTemplate";
      records = osTemplates;
    }
    {
      model = "ClusterResourcePackage";
      records = [
        personalPackage
        godlikePackage
      ];
    }
    {
      model = "ClusterResourcePackageItem";
      records = personalPackageItems ++ godlikePackageItems;
    }
    {
      model = "UserClusterResource";
      records = userClusterResources;
    }
    {
      model = "UserClusterResourcePackage";
      records = userPackageLinks;
    }
  ];
}
