let
  unique =
    list: builtins.foldl' (acc: item: if builtins.elem item acc then acc else acc ++ [ item ]) [ ] list;

  when = condition: tags: if condition then tags else [ ];

  hasPrefix = prefix: str: builtins.substring 0 (builtins.stringLength prefix) str == prefix;

  matches = regex: str: builtins.match regex str != null;

  webuiScriptTags = {
    auth = [
      "auth"
      "webui-auth"
    ];
    userns = [
      "user"
      "userns"
      "webui-userns"
    ];
    vps-lifecycle = [
      "vps"
      "webui-vps"
      "webui-vps-lifecycle"
    ];
    vps-user-core = [
      "user"
      "vps"
      "webui-vps"
      "webui-vps-user-core"
    ];
    vps-user-ops = [
      "user"
      "vps"
      "webui-vps"
      "webui-vps-user-ops"
    ];
    vps-admin-core = [
      "admin"
      "vps"
      "webui-vps"
      "webui-vps-admin-core"
    ];
    vps-admin-ops = [
      "admin"
      "vps"
      "webui-vps"
      "webui-vps-admin-ops"
    ];
    users-self-service = [
      "user"
      "webui-users-self-service"
    ];
    users-admin = [
      "admin"
      "user"
      "webui-users-admin"
    ];
    storage-backup-export = [
      "network-export"
      "storage"
      "storage-backup"
      "webui-storage-backup-export"
    ];
    networking-dns = [
      "dns"
      "network"
      "webui-networking-dns"
    ];
    support-pages = [
      "alerts"
      "monitoring"
      "support"
      "webui-support-pages"
    ];
    misc-pages = [
      "webui-misc-pages"
    ];
    admin-cluster = [
      "admin"
      "cluster"
      "webui-admin-cluster"
    ];
    navigation-readonly = [
      "navigation"
      "webui-navigation-readonly"
    ];
    jumpto = [
      "admin"
      "webui-jumpto"
    ];
    transactions = [
      "tx"
      "webui-transactions"
    ];
  };
in
{
  testTags =
    name:
    unique (
      [ name ]
      ++ when (name == "vpsadmin-services-up") [
        "services"
        "smoke"
      ]
      ++ when (name == "vpsadmin-webui") [ "webui" ]
      ++ when (hasPrefix "vps-" name) [ "vps" ]
      ++ when (matches "vps-.*migrate.*" name) [
        "storage"
        "storage-migrate"
        "vps-migrate"
      ]
      ++ when (matches "vps-.*clone.*" name) [
        "storage"
        "vps-clone"
      ]
      ++ when (matches "vps-.*replace.*" name) [
        "storage"
        "vps-replace"
      ]
      ++
        when
          (matches "vps-.*(create|start|stop|restart|boot|passwd|reinstall|resources|features|deploy|mount|dataset|hard-delete|swap).*" name)
          [ "vps-basic" ]
      ++ when (matches "vps-.*user-data.*" name) [ "vps-user-data" ]
      ++ when (hasPrefix "storage-" name) [ "storage" ]
      ++ when (matches "storage-.*backup.*" name) [ "storage-backup" ]
      ++ when (matches "storage-.*rollback.*" name) [ "storage-rollback" ]
      ++ when (matches "storage-.*restore.*" name) [ "storage-restore" ]
      ++ when (matches "storage-.*snapshot-download.*" name) [ "storage-snapshot-download" ]
      ++ when (matches "storage-.*dataset-migrate.*" name) [ "storage-migrate" ]
      ++ when (matches "storage-.*(destroy|hard-delete).*" name) [ "storage-destroy" ]
      ++ when (matches "storage-.*(topology|branching|complex|history).*" name) [ "storage-topology" ]
      ++ when (matches "storage-.*rotation.*" name) [ "storage-rotation" ]
      ++ when (matches "storage-.*group-snapshot.*" name) [ "storage-group-snapshot" ]
      ++ when (hasPrefix "network-interface-" name) [
        "network"
        "network-interface"
      ]
      ++ when (hasPrefix "export-" name) [
        "network"
        "network-export"
      ]
      ++ when (hasPrefix "dns-" name) [
        "dns"
        "network"
      ]
      ++ when (matches "dns-.*server.*" name) [ "dns-server" ]
      ++ when (matches "dns-.*transfer.*" name) [ "dns-zone-transfer" ]
      ++ when (hasPrefix "user-" name) [ "user" ]
      ++ when (matches ".*auth.*" name) [ "auth" ]
      ++ when (matches ".*user-namespace.*" name) [ "userns" ]
      ++ when (hasPrefix "tx-" name) [ "tx" ]
      ++ when (hasPrefix "admin-" name) [ "admin" ]
      ++ when (matches "admin-.*network.*" name) [
        "network"
        "network-admin"
      ]
      ++ when (matches "admin-.*dataset.*" name) [ "storage" ]
      ++ when (matches "admin-.*nodectl.*" name) [
        "node"
        "nodectl"
        "tx"
      ]
      ++ when (matches "admin-.*remote-mount.*" name) [
        "storage"
        "vps"
      ]
      ++ when (matches "admin-.*scheduler.*" name) [ "scheduler" ]
      ++ when (matches "admin-.*cluster-resource.*" name) [
        "cluster"
        "user"
      ]
      ++ when (hasPrefix "alerts-" name) [ "alerts" ]
      ++ when (matches "alerts-.*oom.*" name) [
        "oom"
        "supervisor"
      ]
      ++ when (hasPrefix "tasks-" name) [ "tasks" ]
      ++ when (matches "tasks-.*auth.*" name) [ "auth" ]
      ++ when (matches "tasks-.*dataset.*" name) [ "storage" ]
      ++ when (matches "tasks-.*dns.*" name) [ "dns" ]
      ++ when (name == "tasks-prometheus-export") [ "monitoring" ]
      ++ when (name == "supervisor-runtime-ingestion") [
        "alerts"
        "network"
        "node"
        "storage"
        "supervisor"
        "vps"
      ]
      ++ when (name == "client-snapshot-download") [
        "client"
        "storage"
        "storage-snapshot-download"
      ]
      ++ when (name == "download-mounter") [
        "download-mounter"
        "storage"
        "storage-snapshot-download"
      ]
      ++ when (name == "console-router") [
        "console-router"
        "vps"
      ]
      ++ when (name == "node-register") [ "node" ]
      ++ when (hasPrefix "node-evacuate-" name) [
        "cluster"
        "node"
      ]
      ++ when (hasPrefix "cluster-" name) [ "cluster" ]
      ++ when (name == "pool-create") [
        "pool"
        "storage"
      ]
    );

  scriptTags =
    testName: scriptName:
    if testName == "vpsadmin-webui" && builtins.hasAttr scriptName webuiScriptTags then
      [ "webui-${scriptName}" ] ++ builtins.getAttr scriptName webuiScriptTags
    else
      [ ];
}
