{
  description = "Network UPS Tools";

  outputs = {
    self,
    nixpkgs,
    ...
  }: {
    defaultPackage.x86_64-linux = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };
      lib = pkgs.lib;
    in
      pkgs.stdenv.mkDerivation rec {
        pname = "nut";
        version = "2.8.0";

        src = pkgs.fetchurl {
          url = "https://networkupstools.org/source/${lib.versions.majorMinor version}/${pname}-${version}.tar.gz";
          sha256 = "sha256-w+WnCNp5e3xwtlPTexIGoAD8tQO4VRn+TN9jU/eSv+U=";
        };

        patches = with pkgs; [
          (substituteAll {
            src = ./hardcode-paths.patch;
            avahi = "${avahi}/lib";
            freeipmi = "${freeipmi}/lib";
            libusb = "${libusb1}/lib";
            neon = "${neon}/lib";
            libmodbus = "${libmodbus}/lib";
            netsnmp = "${net-snmp.lib}/lib";
          })
        ];

        buildInputs = with pkgs; [neon libusb1 openssl udev avahi freeipmi libmodbus i2c-tools net-snmp gd systemd];

        nativeBuildInputs = with pkgs; [autoreconfHook libtool pkg-config makeWrapper];

        configureFlags = [
          "--with-user=ups"
          "--with-group=nut"
          "--with-all"
          "--with-ssl"
          "--without-powerman" # Until we have it ...
          "--with-systemdsystemunitdir=$(out)/lib/systemd/system"
          "--with-systemdshutdowndir=$(out)/lib/systemd/system-shutdown"
          "--with-systemdtmpfilesdir=$(out)/lib/tmpfiles.d"
          "--with-udev-dir=$(out)/lib/udev"
        ];

        enableParallelBuilding = true;

        postInstall = with pkgs; ''
          substituteInPlace $out/lib/systemd/system-shutdown/nutshutdown \
            --replace /bin/sleep "${coreutils}/bin/sleep" \
            --replace /bin/systemctl "${systemd}/bin/systemctl"

          for file in system/{nut-monitor.service,nut-driver-enumerator.service,nut-server.service,nut-driver@.service} system-shutdown/nutshutdown; do
          substituteInPlace $out/lib/systemd/$file \
            --replace "$out/etc/nut.conf" "/etc/nut.conf"
          done

          # we don't need init.d scripts
          rm -r $out/share/solaris-init
        '';

        meta = with lib; {
          description = "Network UPS Tools";
          longDescription = ''
            Network UPS Tools is a collection of programs which provide a common
            interface for monitoring and administering UPS, PDU and SCD hardware.
            It uses a layered approach to connect all of the parts.
          '';
          homepage = "https://networkupstools.org/";
          platforms = platforms.linux;
          maintainers = [maintainers.pierron];
          license = with licenses; [gpl1Plus gpl2Plus gpl3Plus];
          priority = 10;
        };
      };
    nixosModule = let
      nut_pkg = self.defaultPackage.x86_64-linux;
    in
      {
        config,
        lib,
        pkgs,
        ...
      }:
        with lib; let
          cfg = config.rotap.services.nut;
        in let
          upsOptions = {
            name,
            config,
            ...
          }: {
            options = {
              # This can be inferred from the UPS model by looking at
              # /nix/store/nut/share/driver.list
              driver = mkOption {
                type = types.str;
                description = lib.mdDoc ''
                  Specify the program to run to talk to this UPS.  apcsmart,
                  bestups, and sec are some examples.
                '';
              };

              port = mkOption {
                type = types.str;
                description = lib.mdDoc ''
                  The serial port to which your UPS is connected.  /dev/ttyS0 is
                  usually the first port on Linux boxes, for example.
                '';
              };

              shutdownOrder = mkOption {
                default = null;
                type = types.nullOr types.int;
                description = lib.mdDoc ''
                  When you have multiple UPSes on your system, you usually need to
                  turn them off in a certain order.  upsdrvctl shuts down all the
                  0s, then the 1s, 2s, and so on.  To exclude a UPS from the
                  shutdown sequence, set this to -1.
                '';
              };

              maxStartDelay = mkOption {
                default = null;
                type = types.uniq (types.nullOr types.int);
                description = lib.mdDoc ''
                  This can be set as a global variable above your first UPS
                  definition and it can also be set in a UPS section.  This value
                  controls how long upsdrvctl will wait for the driver to finish
                  starting.  This keeps your system from getting stuck due to a
                  broken driver or UPS.
                '';
              };

              description = mkOption {
                default = null;
                type = types.nullOr types.str;
                description = lib.mdDoc ''
                  Description of the UPS.
                '';
              };

              directives = mkOption {
                default = [];
                type = types.listOf types.str;
                description = lib.mdDoc ''
                  List of configuration directives for this UPS.
                '';
              };

              summary = mkOption {
                default = "";
                type = types.lines;
                description = lib.mdDoc ''
                  Lines which would be added inside ups.conf for handling this UPS.
                '';
              };
            };

            config = {
              directives = mkOrder 10 (
                [
                  "driver = ${config.driver}"
                  "port = ${config.port}"
                ]
                ++ (optional (config.description != null)
                  ''desc = "${config.description}"'')
                ++ (optional (config.shutdownOrder != null)
                  "sdorder = ${toString config.shutdownOrder}")
                ++ (optional (config.maxStartDelay != null)
                  "maxstartdelay = ${toString config.maxStartDelay}")
              );

              summary =
                concatStringsSep "\n      "
                (["[${name}]"] ++ config.directives);
            };
          };
        in {
          options.rotap.services.nut = {
            enable = mkOption {
              default = false;
              type = with types; bool;
              description = lib.mdDoc ''
                Enables support for Power Devices, such as Uninterruptible Power
                Supplies, Power Distribution Units and Solar Controllers.
              '';
            };

            schedulerRules = mkOption {
              example = "/etc/nixos/upssched.conf";
              type = types.str;
              default = toString (pkgs.writeText "upssched.conf" ''
                CMDSCRIPT ${nut_pkg}/bin/upssched-cmd
              '');
              description = lib.mdDoc ''
                File which contains the rules to handle UPS events.
              '';
            };

            upsdConfFile = mkOption {
              example = "/etc/nixos/upssched.conf";
              type = types.str;
              description = lib.mdDoc ''
                File which contains upsd configuration.
              '';
            };

            upsdUsersFile = mkOption {
              example = "/etc/nixos/upsd.users";
              type = types.str;
              description = lib.mdDoc ''
                File which contains upsd user configuration.
              '';
            };

            upsmonConfFile = mkOption {
              example = "/etc/nixos/upsmon.conf";
              type = types.str;
              description = lib.mdDoc ''
                File which contains upsmon configuration.
              '';
            };

            maxStartDelay = mkOption {
              default = null;
              type = types.nullOr types.int;
              description = lib.mdDoc ''
                This can be set as a global variable above your first UPS
                definition and it can also be set in a UPS section.  This value
                controls how long upsdrvctl will wait for the driver to finish
                starting.  This keeps your system from getting stuck due to a
                broken driver or UPS.
              '';
            };

            ups = mkOption {
              default = {};
              # see nut/etc/ups.conf.sample
              description = lib.mdDoc ''
                This is where you configure all the UPSes that this system will be
                monitoring directly.  These are usually attached to serial ports,
                but USB devices are also supported.
              '';
              type = with types; attrsOf (submodule upsOptions);
            };
          };

          config = let
            drivers = listToAttrs (mapAttrsToList (name: cfg:
              nameValuePair "nut-driver@${name}" {
                description = ''Network UPS Tools - device driver for %I'';
                after = ["local-fs.target"];
                partOf = ["nut-driver.target"];
                serviceConfig = {
                  EnvironmentFile = "-/etc/nut/nut.conf";
                  SyslogIdentifier = "%N";
                  ExecStart = ''
                    ${pkgs.bashInteractive}/bin/sh -c 'NUTDEV="`${nut_pkg}/libexec/nut-driver-enumerator.sh --get-device-for-service %i`" && [ -n "$NUTDEV" ] || { echo "FATAL: Could not find a NUT device section for service unit %i" >&2 ; exit 1 ; } ; ${nut_pkg}/sbin/upsdrvctl start "$NUTDEV"'
                  '';
                  ExecStop = ''
                    ${pkgs.bashInteractive}/bin/sh -c 'NUTDEV="`${nut_pkg}/libexec/nut-driver-enumerator.sh --get-device-for-service %i`" && [ -n "$NUTDEV" ] || { echo "FATAL: Could not find a NUT device section for service unit %i" >&2 ; exit 1 ; } ; ${nut_pkg}/sbin/upsdrvctl stop "$NUTDEV"'
                  '';
                  StartLimitInterval = "0";
                  Restart = "always";
                  RestartSec = "15s";
                  Type = "forking";
                  # Runtime directory and mode
                  RuntimeDirectory = "nut";
                  RuntimeDirectoryMode = "0750";
                  # State directory and mode
                  StateDirectory = "nut";
                  StateDirectoryMode = "0750";
                  # Configuration directory and mode
                  ConfigurationDirectory = "nut";
                  ConfigurationDirectoryMode = "0750";
                };
                wantedBy = ["nut-driver.target"];
                environment.NUT_CONFPATH = "/etc/nut/";
                environment.NUT_STATEPATH = "/run/nut/";
              })
            cfg.ups);
          in
            mkIf cfg.enable {
              environment.systemPackages = [nut_pkg];

              services.udev.packages = [nut_pkg];

              systemd.targets.nut = {
                description = "Network UPS Tools - target for power device drivers, data server and monitoring client (if enabled) on this system";
                after = ["local-fs.target" "nut-driver.target" "nut-server.target" "nut-monitor.target"];
                wants = ["local-fs.target" "nut-driver.target" "nut-server.target" "nut-monitor.target"];
                wantedBy = ["multi-user.target"];
              };

              systemd.targets.nut-driver = {
                description = "Network UPS Tools - target for power device drivers on this system";
                after = ["local-fs.target"];
                partOf = ["nut.target"];
                wantedBy = ["nut.target"];
              };

              systemd.services =
                {
                  nut-monitor = {
                    description = "Network UPS Tools - power device monitor and shutdown controller";
                    after = ["local-fs.target" "network.target" "nut-server.target"];
                    wants = ["nut-server.service"];
                    partOf = ["nut.target"];
                    serviceConfig = {
                      EnvironmentFile = "-/etc/nut/nut.conf";
                      SyslogIdentifier = "%N";
                      ExecStart = "${nut_pkg}/sbin/upsmon -F";
                      ExecReload = "${nut_pkg}/sbin/upsmon -c reload";
                      PIDFile = "/run/nut/upsmon.pid";
                    };
                    wantedBy = ["nut.target"];
                    environment.NUT_CONFPATH = "/etc/nut/";
                    environment.NUT_STATEPATH = "/run/nut/";
                  };

                  nut-server = {
                    description = "Network UPS Tools - power devices information server";
                    after = ["local-fs.target" "network.target" "nut-driver.target"];
                    wants = ["nut-driver.target"];
                    requires = ["network.target"];
                    before = ["nut-monitor.target"];
                    partOf = ["nut.target"];
                    serviceConfig = {
                      EnvironmentFile = "-/etc/nut/nut.conf";
                      SyslogIdentifier = "%N";
                      ExecStart = "${nut_pkg}/sbin/upsd -F";
                      ExecReload = "${nut_pkg}/sbin/upsd -c reload -P $MAINPID";
                      PIDFile = "/run/nut/upsd.pid";
                      User = "ups";
                      Group = "nut";
                      # Runtime directory and mode
                      RuntimeDirectory = "nut";
                      RuntimeDirectoryMode = "0750";
                      RuntimeDirectoryPreserve = "yes";
                      # State directory and mode
                      StateDirectory = "nut";
                      StateDirectoryMode = "0750";
                      # Configuration directory and mode
                      ConfigurationDirectory = "nut";
                      ConfigurationDirectoryMode = "0750";
                    };
                    wantedBy = ["nut.target"];
                    environment.NUT_CONFPATH = "/etc/nut/";
                    environment.NUT_STATEPATH = "/run/nut/";
                  };
                }
                // drivers;

              environment.etc = {
                "nut/nut.conf".source =
                  pkgs.writeText "nut.conf"
                  ''
                    MODE = standalone
                  '';
                "nut/ups.conf".source = pkgs.writeText "ups.conf" ((
                    if cfg.maxStartDelay != null
                    then "maxstartdelay = ${toString cfg.maxStartDelay}"
                    else ""
                  )
                  + ''

                    ${flip concatStringsSep (forEach (attrValues cfg.ups) (ups: ups.summary)) "

                  "}
                  '');
                "nut/upssched.conf".source = cfg.schedulerRules;
                # These file may contain private information and thus should not
                # be stored inside the Nix store.
                "nut/upsd.conf".source = cfg.upsdConfFile;
                "nut/upsd.users".source = cfg.upsdUsersFile;
                "nut/upsmon.conf".source = cfg.upsmonConfFile;
              };

              users.users.ups = {
                # TODO: Specify this UID somewhere.
                uid = 991;
                isSystemUser = true;
                group = "nut";
                description = "UPnP A/V Media Server user";
              };

              # TODO: Specify this GID somewhere.
              users.groups."nut" = {gid = 991;};
            };
        };
  };
}
