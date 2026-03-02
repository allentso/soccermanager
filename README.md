<div align="center">

![Openfoot logo](images/openfootlogo.svg)

[![License: GPL v3](https://img.shields.io/github/license/openfootmanager/openfootmanager
)](https://www.gnu.org/licenses/gpl-3.0)
[![Rust](https://shields.io/badge/-Rust-FF4500?style=flat&logo=rust)](https://www.rust-lang.org/)
[![Tauri](https://shields.io/badge/-Tauri-2E8B57?style=flat&logo=tauri)](https://tauri.app/)
[![React](https://shields.io/badge/-React-1434A4?style=flat&logo=react)](https://react.dev/)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://GitHub.com/openfootmanager/openfootmanager/graphs/commit-activity)
[![Last commit](https://img.shields.io/github/last-commit/openfootmanager/openfootmanager)](https://github.com/openfootmanager/openfootmanager/commits/develop)

**A free and open source football management simulation game**

[Features](#features) • [Screenshots](#screenshots) • [Installation](#installation) • [Contributing](#contributing) • [License](#license)

</div>

---

**Openfoot Manager** is a free and open source football/soccer manager game, licensed under the [GPLv3](LICENSE.md), inspired by the famous franchise Football Manager&trade;.

## ARCHITECTURE

OpenFootManager is built using modern web technologies:

- **Rust**: Blazing-fast backend for the Match Simulation Engine and Game State.
- **Tauri**: Lightweight desktop application shell.
- **React + TypeScript + TailwindCSS**: A highly responsive frontend interface.
- **SQLite**: Local persistence for game saves.

## INSTALLATION & DEVELOPMENT

The game is still in early active development. To build and run the debug version, you need to install standard tools for Rust, Node, and Tauri development:

1. Install **Rust** (via `rustup`)
2. Install **Node.js** (v18+)
3. Install Tauri dependencies for your specific OS (see the [Tauri Prerequisites Guide](https://v2.tauri.app/start/prerequisites/))

Clone the repository and install dependencies:

```bash
git clone https://github.com/openfootmanager/openfootmanager.git
cd openfootmanager
npm install
```

Run the development desktop app:

```bash
npm run tauri dev
```

## CONTRIBUTING

Check the [CONTRIBUTING](CONTRIBUTING.md) file for more information on how to contribute.

## LICENSE

    Openfoot Manager - A free and open source soccer management game
    Copyright (C) 2020-2026  Pedrenrique G. Guimarães

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

Check [LICENSE](LICENSE.md) for more information.
