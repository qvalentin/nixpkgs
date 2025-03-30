{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.spliit;
in
{
  options.services.spliit = with lib; {
    enable = mkEnableOption (mdDoc "Spliit bill-splitting web application");
    package = mkPackageOption pkgs "spliit" { };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = mdDoc "Port to listen on.";
    };

    user = mkOption {
      type = types.str;
      default = "spliit";
      description = mdDoc "User account under which Spliit runs.";
    };

    group = mkOption {
      type = types.str;
      default = "spliit";
      description = mdDoc "Group under which Spliit runs.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc "Whether to open the firewall for the specified port.";
    };

    configureNginx = mkOption {
      type = types.bool;
      default = true;
      description = "Configure nginx as a reverse proxy for Spliit.";
    };

    host = mkOption {
      type = lib.types.str;
      description = "Domain on which nginx will serve Spliit";
    };

    database = {
      createLocally = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Create the PostgreSQL database and database user locally.
        '';
      };
      hostname = mkOption {
        type = types.str;
        default = "/run/postgresql";
        description = "Database hostname.";
      };
      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Database port.";
      };
      name = mkOption {
        type = types.str;
        default = "spliit";
        description = "Database name.";
      };
      user = mkOption {
        type = types.str;
        default = "spliit";
        description = "Database user.";
      };
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/keys/spliit-dbpassword";
        description = ''
          A file containing the password corresponding to
          [](#opt-services.spliit.database.user).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.spliit = {
      description = "Spliit bill-splitting web application";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ] ++ lib.optional cfg.database.createLocally "postgresql.service";
      requires = lib.mkIf cfg.database.createLocally [ "postgresql.service" ];

      environment = lib.mkMerge [
        (lib.mkIf cfg.database.createLocally {
          POSTGRES_PRISMA_URL = "postgresql://${cfg.database.user}@${cfg.database.name}/${cfg.database.name}?host=/var/run/postgresql/";
          POSTGRES_URL_NON_POOLING = "postgresql://${cfg.database.user}@${cfg.database.name}/${cfg.database.name}?host=/var/run/postgresql/";
        })
        (lib.mkIf (!cfg.database.createLocally) {
          db_host = cfg.database.hostname;
          db_port = toString cfg.database.port;
          POSTGRES_PRISMA_URL = "postgresql://${cfg.database.user}:${cfg.database.passwordFile}@${cfg.database.name}?host=${cfg.database.hostname}";
          POSTGRES_URL_NON_POOLING = "postgresql://${cfg.database.user}:${cfg.database.passwordFile}@${cfg.database.name}?host=${cfg.database.hostname}";
        })
        {
          PORT = toString cfg.port;
        }
      ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        StateDirectory = "spliit";
        ExecStart = lib.getExe cfg.package;
        Restart = "always";
        RestartSec = "10";
        User = cfg.user;
        Group = cfg.group;

        # Hardening
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };

    services.postgresql = lib.mkIf cfg.database.createLocally {
      enable = true;
      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    users.groups = lib.mkIf (cfg.group == "spliit") {
      spliit = { };
    };

    users.users = {
      ${cfg.user} = {
        group = cfg.group;
        isSystemUser = true;
        description = "Spliit daemon user";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };

}
