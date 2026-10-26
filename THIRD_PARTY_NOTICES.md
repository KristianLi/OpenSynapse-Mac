# Third-party notices

## OpenSynapse

- Project: https://github.com/A1mAssist/OpenSynapse
- License: MIT, Copyright (c) 2026 OpenSynapse contributors
- Use: The protocol layer, device catalog loader, capability resolution and device
  services in `Sources/RazerCore` are a Swift translation of OpenSynapse's C# code
  (upstream commit `117af46`). Product lists and protocol constants for the
  protocol 25 keyboard, audio and Chroma families come from the same project.

The MIT license text and the OpenSynapse copyright notice are reproduced in
[LICENSE](LICENSE).

## OpenRazer

- Project: https://github.com/openrazer/openrazer
- License: GNU General Public License v2.0 or later (`GPL-2.0-or-later`)
- Use: `Sources/RazerCore/Resources/{mice,keyboards,laptops,accessories}.json` are
  device data (product IDs, capability sets, transaction IDs, LED zones, matrix
  sizes) extracted from the OpenRazer driver at commit
  `477f4d6d3ab7e9deb6310d5bd3742560c5cbe80d`, as packaged by OpenSynapse.
  These files keep OpenRazer's license. The command builders in this project are
  named after the OpenRazer functions they reproduce on the wire.

A copy of the GPL v2 is available at https://www.gnu.org/licenses/old-licenses/gpl-2.0.html.

## Trademarks

This project is not affiliated with, endorsed by, or sponsored by Razer Inc.
Razer, Synapse, Chroma, Kraken, Basilisk, BlackShark and other product names are
trademarks of their respective owners and are used only to identify compatible
hardware.

No Razer software, drivers, firmware or other proprietary files are included in
this repository. Protocol details come from the open-source projects above and
from black-box testing of devices owned by the author.
