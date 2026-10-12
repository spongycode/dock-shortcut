# dock-shortcut

Windows-style `Cmd + 1..9` shortcuts to launch and switch between macOS Dock apps.

## Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`Cmd + 1` ... `9`** | Focus / launch Dock app at slot 1 to 9 (cycles open windows/tabs on repeat) |
| **`Cmd + 0`** | Focus Finder |

## Setup

1. Install [Hammerspoon](https://www.hammerspoon.org/):
   ```bash
   brew install --cask hammerspoon
   ```

2. Link `init.lua`:
   ```bash
   mkdir -p ~/.hammerspoon
   ln -sf "$(pwd)/init.lua" ~/.hammerspoon/init.lua
   ```

3. Enable **Hammerspoon** in **System Settings → Privacy & Security → Accessibility**.

## License

MIT
