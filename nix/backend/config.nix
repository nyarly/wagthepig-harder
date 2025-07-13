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
    maybeSMTPCert =
      if cfg.smtp.certPath != null then
        {
          SMTP_CERT = cfg.smtp.certPath;
        }
      else
        { };
    dbPass = if cfg.database.passwordPath == null then "" else ":$(cat ${cfg.database.passwordPath})";

    dbURL = "export DATABASE_URL=postgres:///${cfg.database.user}${dbPass}@${cfg.database.host}:${cfg.database.port}/${cfg.database.name}";
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
        "postgresql.service"
      ];
      wants = [ ];

      wantedBy = [ "multi-user.target" ];

      environment =
        {
          LOCAL_ADDR = "${cfg.listen.host}:${cfg.listen.port}";
          CANON_DOMAIN = cfg.canonDomain;
          TRUST_FORWARDED_HEADER = cfg.trustForwarded;
          AUTH_KEYPAIR = "%S/wagthepig/backend.keypair";
          ADMIN_EMAIL = cfg.adminEmail;
          SMTP_HOST = cfg.smtp.host;
          SMTP_PORT = cfg.smtp.port;
          SMTP_USERNAME = cfg.smtp.username;
        }
        // cfg.extraEnvironment
        // maybeSMTPCert;

      preStart = ''
        mkdir -p %S/wagthepig
        chown ${cfg.user}:${cfg.group} -R %S/wagthepig

        ${pkgs.psql} -h cfg.database.host -p cfg.database.port -U postgres <<SQL
        create user if not exists ${cfg.database.user};
        create database if not exists ${cfg.database.name} with owner ${cfg.database.user};
        SQL

        ${dbURL}
        ${pkgs.sqlx} migrate run --source ${package.migrations}
      '';

      script = ''
        ${dbURL}
        export SMTP_PASSWORD=$(cat ${cfg.smtp.passwordPath})
        ${package}/bin/wagthepig-backend
      '';
    };
  }
)
