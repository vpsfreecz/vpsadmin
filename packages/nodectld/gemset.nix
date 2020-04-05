{
  coderay = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "15vav4bhcc2x3jmi3izb11l4d9f3xv8hp2fszb7iqmpsccv1pz4y";
      type = "gem";
    };
    version = "1.1.2";
  };
  curses = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0hic9kq09dhh8jqjx3k1991rnqhlj3glz82w0g7ndcri52m1hgqg";
      type = "gem";
    };
    version = "1.3.2";
  };
  eventmachine = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0wh9aqb0skz80fhfn66lbpr4f86ya2z5rx6gm5xlfhd05bj1ch4r";
      type = "gem";
    };
    version = "1.2.7";
  };
  filelock = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "085vrb6wf243iqqnrrccwhjd4chphfdsybkvjbapa2ipfj1ja1sj";
      type = "gem";
    };
    version = "1.1.1";
  };
  gli = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1sgfc8czb7xk0sdnnz7vn61q4ixbkrpz2mkvcgchfkll94rlqhal";
      type = "gem";
    };
    version = "2.17.2";
  };
  highline = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "01ib7jp85xjc4gh4jg0wyzllm46hwv8p0w1m4c75pbgi41fps50y";
      type = "gem";
    };
    version = "1.7.10";
  };
  ipaddress = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1x86s0s11w202j6ka40jbmywkrx8fhq8xiy8mwvnkhllj57hqr45";
      type = "gem";
    };
    version = "0.8.3";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0nrmw2r4nfxlfgprfgki3hjifgrcrs3l5zvm3ca3gb4743yr25mn";
      type = "gem";
    };
    version = "2.3.0";
  };
  libnodectld = {
    dependencies = ["eventmachine" "filelock" "ipaddress" "json" "libosctl" "mail" "mysql2" "osctl" "osctl-exportfs" "pry" "pry-remote" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "17ckkqhbm8f0lak9nyd249n9ragariq4xwdgqrzxmpiy14026903";
      type = "gem";
    };
    version = "3.0.0.dev.build20200405111328";
  };
  libosctl = {
    dependencies = ["rainbow" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1lhya6aazlw3ifmwyiidqvpvrpyaicia4v4sikdmjn84ldpgv7di";
      type = "gem";
    };
    version = "19.09.0.build20200404204258";
  };
  mail = {
    dependencies = ["mini_mime"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "00wwz6ys0502dpk8xprwcqfwyf3hmnx6lgxaiq6vj43mkx43sapc";
      type = "gem";
    };
    version = "2.7.1";
  };
  method_source = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1pviwzvdqd90gn6y7illcdd9adapw8fczml933p5vl739dkvl3lq";
      type = "gem";
    };
    version = "0.9.2";
  };
  mini_mime = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1axm0rxyx3ss93wbmfkm78a6x03l8y4qy60rhkkiq0aza0vwq3ha";
      type = "gem";
    };
    version = "1.0.2";
  };
  mysql2 = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0d14pcy5m4hjig0zdxnl9in5f4izszc7v9zcczf2gyi5kiyxk8jw";
      type = "gem";
    };
    version = "0.5.3";
  };
  nodectld = {
    dependencies = ["libnodectld"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1hdnmhgyl0gldamrdwmbvp8v10vf4y4vy8bz8p4n2fy70phbi792";
      type = "gem";
    };
    version = "3.0.0.dev.build20200405111328";
  };
  osctl = {
    dependencies = ["curses" "gli" "highline" "ipaddress" "json" "libosctl" "rainbow" "require_all" "ruby-progressbar"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1qflqf18pwfzgz3dlincq3422qc5a2ysia3blfridr9kmw46fwx9";
      type = "gem";
    };
    version = "19.09.0.build20200404204258";
  };
  osctl-exportfs = {
    dependencies = ["filelock" "gli" "libosctl" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1s64inkpiwz4851gcq66mwbclbjyhjbnnx050qpyw42d0zna57qg";
      type = "gem";
    };
    version = "19.09.0.build20200404204258";
  };
  pry = {
    dependencies = ["coderay" "method_source"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1mh312k3y94sj0pi160wpia0ps8f4kmzvm505i6bvwynfdh7v30g";
      type = "gem";
    };
    version = "0.11.3";
  };
  pry-remote = {
    dependencies = ["pry" "slop"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "10g1wrkcy5v5qyg9fpw1cag6g5rlcl1i66kn00r7kwqkzrdhd7nm";
      type = "gem";
    };
    version = "0.1.8";
  };
  rainbow = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0bb2fpjspydr6x0s8pn1pqkzmxszvkfapv0p4627mywl7ky4zkhk";
      type = "gem";
    };
    version = "3.0.0";
  };
  require_all = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0sjf2vigdg4wq7z0xlw14zyhcz4992s05wgr2s58kjgin12bkmv8";
      type = "gem";
    };
    version = "2.0.0";
  };
  ruby-progressbar = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "1igh1xivf5h5g3y5m9b4i4j2mhz2r43kngh4ww3q1r80ch21nbfk";
      type = "gem";
    };
    version = "1.9.0";
  };
  slop = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "00w8g3j7k7kl8ri2cf1m58ckxk8rn350gp4chfscmgv6pq1spk3n";
      type = "gem";
    };
    version = "3.6.0";
  };
}