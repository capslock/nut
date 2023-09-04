{
  description = "A template that shows all standard flake outputs";

  outputs = {nixpkgs, ...}: {
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

        buildInputs = with pkgs; [neon libusb1 openssl udev avahi freeipmi libmodbus i2c-tools net-snmp gd];

        nativeBuildInputs = with pkgs; [autoreconfHook libtool pkg-config makeWrapper];

        configureFlags = [
          "--with-all"
          "--with-ssl"
          "--without-powerman" # Until we have it ...
          "--with-systemdsystemunitdir=$(out)/lib/systemd/system"
          "--with-systemdshutdowndir=$(out)/lib/systemd/system-shutdown"
          "--with-systemdtmpfilesdir=$(out)/lib/tmpfiles.d"
          "--with-udev-dir=$(out)/etc/udev"
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
  };
}
