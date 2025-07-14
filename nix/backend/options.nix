self-packages:
{
  lib,
  ...
}:
let
  inherit (lib) mkOption mkEnableOption;
  inherit (lib.types)
    str
    submodule
    port
    bool
    attrsOf
    nullOr
    package
    ;
in
{
  services.wag-the-pig = {
    enable = mkEnableOption { name = "wagthepig"; };
    package = mkOption {
      type = package;
      default = self-packages.wag-the-pig;
    };
    user = mkOption {
      type = str;
      default = "wagthepig";
    };
    group = mkOption {
      type = str;
      default = "wagthepig";
    };
    adminEmail = mkOption {
      type = str;
      example = "admin@wagthepig.com";
    };
    canonDomain = mkOption {
      type = str;
      example = "wagthepig.com";
      default = "wagthepig.com";
    };
    trustForwarded = mkOption {
      type = bool;
      description = ''
        The backend does rate limiting based on the IP of the requester.
        If you're running behind a reverse proxy (e.g. httpd or nginx),
        you should configure it to send Forwarded headers, and set this to true.
        If you're running it on its own, set this as false so that bad actors
        can't construct requests with Forwarded headers to evade rate limiting.
      '';
    };
    extraEnvironment = mkOption {
      type = attrsOf str;
      default = { };
    };
    listen = mkOption {
      description = "the address and port to listen on";

      default = { };
      type = submodule {
        options = {
          host = mkOption {
            type = str;
            default = "127.0.0.1";
          };
          port = mkOption {
            type = port;
            default = 3000;
          };
        };
      };
    };
    database = mkOption {
      description = "Configuration for the required PostgreSQL database.";

      default = { };
      type = submodule {
        options = {
          user = mkOption {
            type = str;
            default = "wagthepig";
          };
          host = mkOption {
            type = str;
            default = "localhost";
          };
          port = mkOption {
            type = port;
            default = 5432;
          };
          name = mkOption {
            type = str;
            default = "wagthepig";
          };
          passwordPath = mkOption {
            type = nullOr str;
            default = null;
          };
        };
      };
    };
    smtp = mkOption {
      description = "configuration details for an SMTP MTA, used to send account updates etc with.";
      type = submodule {
        options = {
          host = mkOption {
            type = str;
            description = "the MTA host";
          };
          port = mkOption {
            type = port;
            default = 1025;
          };
          username = mkOption {
            type = str;
          };
          # goes into SOPS
          passwordPath = mkOption {
            type = str;
          };
          # have to make this optional...
          certPath = mkOption {
            type = nullOr str;
            description = "the path to find the SMTP certificate";
            default = null;
          };
        };
      };
    };
  };
}
