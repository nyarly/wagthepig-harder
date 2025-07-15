{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.services.wag-the-pig.enable (
  let
    cfg = config.services.wag-the-pig;
    package = cfg.package;
    maybeSMTPCert =
      if cfg.smtp.certPath != null then
        {
          SMTP_CERT = cfg.smtp.certPath;
        }
      else
        { };
    dbPass = if cfg.database.passwordPath == null then "" else ":$(cat ${cfg.database.passwordPath})";

    dbURL = "export DATABASE_URL=postgres://${cfg.database.user}${dbPass}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";
  in
  {
    users = {
      users = {
        "${cfg.user}" = {
          name = cfg.user;
          group = cfg.group;
          extraGroups = [ "keys" ];
          isSystemUser = true;
        };
      };

      groups = {
        "${cfg.group}" = { };
      };
    };

    systemd.services.wag-the-pig =
      let
        preStart =
          (pkgs.writeShellScriptBin "wagthepig-prestart"
            #bash
            ''
              set -e

              ${pkgs.postgresql}/bin/psql -h ${cfg.database.host} -p ${toString cfg.database.port} -U postgres <<'SQL'
              do $$
              begin
                create role ${cfg.database.user};
                exception when duplicate_object then raise notice '%, skipping', sqlerrm using errcode = SQLSTATE;
              end
              $$;
              SQL

              ${pkgs.postgresql}/bin/psql -h ${cfg.database.host} -p ${toString cfg.database.port} -U postgres <<'SQL' || echo "already exists"
              create database ${cfg.database.name} with owner ${cfg.database.user};
              SQL

              ${dbURL}
              ${pkgs.sqlx-cli}/bin/sqlx migrate run --source ${package.migrations}
            ''
          ).overrideAttrs
            (_: {
              name = "unit-script-wagthepig-prestart";
            });
      in
      {
        after = [
          "network.target"
          "postgresql.service"
        ];
        wants = [ ];

        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          StateDirectory = "wag-the-pig";
          User = cfg.user;
          Group = cfg.group;
          ExecStartPre = [ "!${lib.getExe preStart}" ];
        };

        environment =
          {
            LOCAL_ADDR = "${cfg.listen.host}:${toString cfg.listen.port}";
            CANON_DOMAIN = cfg.canonDomain;
            TRUST_FORWARDED_HEADER = lib.boolToString cfg.trustForwarded;
            AUTH_KEYPAIR = "%S/wag-the-pig/backend.keypair";
            ADMIN_EMAIL = cfg.adminEmail;
            SMTP_HOST = cfg.smtp.host;
            SMTP_PORT = toString cfg.smtp.port;
            SMTP_USERNAME = cfg.smtp.username;
          }
          // cfg.extraEnvironment
          // maybeSMTPCert;

        script = ''
          ${dbURL}
          export SMTP_PASSWORD=$(cat ${cfg.smtp.passwordPath})
          ${package}/bin/wagthepig-backend
        '';
      };
  }
)
