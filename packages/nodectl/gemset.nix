{
  coderay = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "15vav4bhcc2x3jmi3izb11l4d9f3xv8hp2fszb7iqmpsccv1pz4y";
      type = "gem";
    };
    version = "1.1.2";
  };
  curses = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0hdgz18a21wi2hg5aw8abc012ni055jr1fbam0v2r8nsqsnx8dy2";
      type = "gem";
    };
    version = "1.2.4";
  };
  eventmachine = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "08477hl609rmmngwfy8dmsqz5zvsg8xrsrrk6xi70jf48majwli0";
      type = "gem";
    };
    version = "1.2.6";
  };
  gli = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0g7g3lxhh2b4h4im58zywj9vcfixfgndfsvp84cr3x67b5zm4kaq";
      type = "gem";
    };
    version = "2.17.1";
  };
  highline = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "01ib7jp85xjc4gh4jg0wyzllm46hwv8p0w1m4c75pbgi41fps50y";
      type = "gem";
    };
    version = "1.7.10";
  };
  ipaddress = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1x86s0s11w202j6ka40jbmywkrx8fhq8xiy8mwvnkhllj57hqr45";
      type = "gem";
    };
    version = "0.8.3";
  };
  json = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "01v6jjpvh3gnq6sgllpfqahlgxzj50ailwhj9b3cd20hi2dx0vxp";
      type = "gem";
    };
    version = "2.1.0";
  };
  libnodectld = {
    dependencies = ["eventmachine" "json" "libosctl" "mail" "mysql2" "osctl" "pry-remote" "require_all"];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1frvwxdpspfs97cfjmhsk8hkalzh5ly8ypx9kf8lr4shq97bbqsl";
      type = "gem";
    };
    version = "3.0.0.dev.build20180502145328";
  };
  libosctl = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1mmzs3rqxwwvr2193mldafsyzv890gw8g4q4541sg46y1cpl4yy2";
      type = "gem";
    };
    version = "18.03.0.build20180430140815";
  };
  mail = {
    dependencies = ["mini_mime"];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "10dyifazss9mgdzdv08p47p344wmphp5pkh5i73s7c04ra8y6ahz";
      type = "gem";
    };
    version = "2.7.0";
  };
  method_source = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0xqj21j3vfq4ldia6i2akhn2qd84m0iqcnsl49kfpq3xk6x0dzgn";
      type = "gem";
    };
    version = "0.9.0";
  };
  mini_mime = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1lwhlvjqaqfm6k3ms4v29sby9y7m518ylsqz2j74i740715yl5c8";
      type = "gem";
    };
    version = "1.0.0";
  };
  mysql2 = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1sg4mq40pnnd38qx195gsaxxw4g0blpvlbhagysd18f3xhfpajzc";
      type = "gem";
    };
    version = "0.5.1";
  };
  nodectl = {
    dependencies = ["json" "libnodectld" "pry-remote" "require_all"];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1v3wcaxjx4mdfq8v1xvyprsiala4xx9j30q1x7cj0i0blx0dbghk";
      type = "gem";
    };
    version = "3.0.0.dev.build20180502145328";
  };
  osctl = {
    dependencies = ["curses" "gli" "highline" "ipaddress" "json" "rainbow" "ruby-progressbar"];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "196xy7c1xgyx3h58wc7frbf44dqfpm1p9lvw94nl8x6wpxp78bx6";
      type = "gem";
    };
    version = "18.03.0.build20180430140815";
  };
  pry = {
    dependencies = ["coderay" "method_source"];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1mh312k3y94sj0pi160wpia0ps8f4kmzvm505i6bvwynfdh7v30g";
      type = "gem";
    };
    version = "0.11.3";
  };
  pry-remote = {
    dependencies = ["pry" "slop"];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "10g1wrkcy5v5qyg9fpw1cag6g5rlcl1i66kn00r7kwqkzrdhd7nm";
      type = "gem";
    };
    version = "0.1.8";
  };
  rainbow = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0bb2fpjspydr6x0s8pn1pqkzmxszvkfapv0p4627mywl7ky4zkhk";
      type = "gem";
    };
    version = "3.0.0";
  };
  require_all = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0sjf2vigdg4wq7z0xlw14zyhcz4992s05wgr2s58kjgin12bkmv8";
      type = "gem";
    };
    version = "2.0.0";
  };
  ruby-progressbar = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1igh1xivf5h5g3y5m9b4i4j2mhz2r43kngh4ww3q1r80ch21nbfk";
      type = "gem";
    };
    version = "1.9.0";
  };
  slop = {
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "00w8g3j7k7kl8ri2cf1m58ckxk8rn350gp4chfscmgv6pq1spk3n";
      type = "gem";
    };
    version = "3.6.0";
  };
}