# Defaults duplicated by existing Nix options, not an exhaustive action registry.
# Ruby validates these values at runtime; other registered actions use Ruby defaults.
{
  email = {
    concurrency = 2;
    rate_limits = {
      minute = 30;
      hour = 300;
      day = 2000;
      week = 5000;
    };
  };
  webhook = {
    concurrency = 4;
    rate_limits = {
      minute = 60;
      hour = 1000;
      day = 10000;
      week = 25000;
    };
  };
  telegram = {
    concurrency = 2;
    rate_limits = {
      minute = 20;
      hour = 200;
      day = 1000;
      week = 2500;
    };
  };
  sms = {
    concurrency = 1;
    rate_limits = {
      minute = 3;
      hour = 30;
      day = 150;
      week = 300;
    };
  };
}
