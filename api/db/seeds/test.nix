let
  adminUser = {
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
      records = [
        {
          name = "memory";
          label = "Memory";
          min = 1024;
          max = 12 * 1024;
          stepsize = 1024;
          resource_type = "numeric";
        }
        {
          name = "swap";
          label = "Swap";
          min = 0;
          max = 12 * 1024;
          stepsize = 1024;
          resource_type = "numeric";
        }
        {
          name = "cpu";
          label = "CPU";
          min = 1;
          max = 8;
          stepsize = 1;
          resource_type = "numeric";
        }
        {
          name = "diskspace";
          label = "Disk space";
          min = 10 * 1024;
          max = 2000 * 1024;
          stepsize = 10 * 1024;
          resource_type = "numeric";
        }
      ];
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
  ];
}
