let
  secretsDir = "/etc/vpsadmin-test";

  mkDbUser = user: password: {
    inherit user password;
    passwordFile = "${secretsDir}/mariadb-${user}-password";
  };

  mkRabbitUser = user: password: {
    inherit user password;
    passwordFile = "${secretsDir}/rabbitmq-${user}-password";
  };
in
{
  inherit secretsDir;

  database = {
    name = "vpsadmin";
    users = {
      api = mkDbUser "api" "testMariadbApiPassword";
      supervisor = mkDbUser "supervisor" "testMariadbSupervisorPassword";
      nodectld = mkDbUser "nodectld" "testMariadbNodectldPassword";
    };
  };

  rabbitmq = {
    vhost = "vpsadmin_test";
    users = {
      admin = mkRabbitUser "admin" "testRabbitmqAdminPassword";
      api = mkRabbitUser "api" "testRabbitmqApiPassword";
      supervisor = mkRabbitUser "supervisor" "testRabbitmqSupervisorPassword";
      console = mkRabbitUser "console" "testRabbitmqConsolePassword";
      vnc = mkRabbitUser "vnc" "testRabbitmqVncPassword";
      node = mkRabbitUser "node" "testRabbitmqNodePassword";
    };
  };

  redis = {
    password = "testRedisPassword";
    passwordFile = "${secretsDir}/redis-password";
  };
}
