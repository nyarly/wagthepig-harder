{
config,
lib,
pkgs,
...
}:
lib.mkIf config.services.wagthepig.enable (
  let
    cfg = config.services.wagthepig;
    package = cfg.package;
  in
    {
    users = {
      users = {
        "${cfg.user}" = {
          name = cfg.user;
          group = cfg.group;
          extraGroups = [ "keys" ];
          home = "${cfg.statePath}";
          isSystemUser = true;
        };
      };

      groups = {
        "${cfg.group}" = { };
      };
    };

    systemd.services.wagthepig = {
      after = [
        "network.target"
      ];
      wants = [ ];

      wantedBy = [ "multi-user.target" ];

      environmentFile = config.sops.secrets."wagthepig.env".path;

      environment = {
        CANON_DOMAIN = cfg.canonDomain;
        TRUST_FORWARDED_HEADER = cfg.trustForwarded;
        AUTH_KEYPAIR = "${cfg.statePath}/backend.keypair";
        ADMIN_EMAIL = cfg.adminEmail;
        SMTP_HOST = cfg.smtp.host;
        SMTP_PORT = cfg.smtp.port;
        SMTP_USERNAME = cfg.smtp.username;
        SMTP_CERT = cfg.smtp.certPath;
        # default config deploys with localhost trust; needs a password config one day
        DATABASE_URL = "postgres:///${cfg.database.user}?host=${cfg.database.host}:${cfg.database.port}/${cfg.database.name}";
      } // cfg.extraEnvironment;

      preStart = ''
        mkdir -p ${cfg.statePath}
        chown ${cfg.user}:${cfg.group} -R ${cfg.statePath}

        ${pkgs.psql} -h cfg.database.host -p cfg.database.port <<SQL
        create user ${cfg.database.user};
        create database ${cfg.database.name} with owner ${cfg.database.user};
        SQL

        pushd ${package.migrations};
        ${pkgs.sqlx} migrate run
        popd
        '';

      script = ''
        export SMTP_PASSWORD=$(cat ${cfg.smtp.passwordPath})
        ${package}/bin/wagthepig-backend
        '';
    };
  }
)
