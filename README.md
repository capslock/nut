# NixOS Flake for NUT (Network UPS Tools)

## Brief Description

This is a NixOS flake that enhances the existing NUT (Network UPS Tools) package and service on NixOS. It aims to address various deficiencies such as incomplete configuration options, service definition issues, and the service running as root.

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
- [Code Structure](#code-structure)
- [Contributing](#contributing)
- [License](#license)

## Installation

To use this flake, add it to your `flake.nix` file:

```nix

{
  inputs.nut.url = "github:capslock/nut";
  outputs = { self, nixpkgs, nut }: {
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      modules = [
        ({
          config,
          pkgs,
          ...
        }: {nixpkgs.overlays = [nut.overlays.default];})
        ./configuration.nix
        nut.nixosModules.default
      ];
    };
  };
}
```

## Usage

Now you can configure `NUT` in your NixOS `configuration.nix`, e.g.:

TODO: Explain/make this example better.

```nix
{
  services.nut = {
    enable = true;
    ups."Eaton5S" = {
      driver = "usbhid-ups";
      port = "auto";
      description = "Eaton 5S";
    };
    upsdConfFile = toString (pkgs.writeText "upsd.conf" "");
    upsdUsersFile = config.sops.templates."upsd.users".path;
    upsmonConfFile = config.sops.templates."upsmon.conf".path;
  };
}
```

## Code Structure

- `flake.nix` - Flake containing updated package and module definitions.

## Contributing

1. Fork the repository.
2. Create your feature branch (`git checkout -b my-feature`).
3. Commit your changes (`git commit -m 'Add some feature'`).
4. Push to the feature branch (`git push origin my-feature`).
5. Open a pull request.

## License

This project is licensed under the MIT License - see the
[LICENSE.md](LICENSE.md) file for details.