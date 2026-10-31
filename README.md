<!-- <p align="center">
<img src="./assets/ambxst/ambxst-banner.png" alt="Ambxst Logo" style="width: 60%;" align="center" />
  <br>
An <i><b>Ax</b>tremely</i> customizable shell.
</p> -->




<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis/master/Emojis/Objects/Camera%20with%20Flash.png" alt="Camera with Flash" width="32" height="32" /></sub> Screenshots</h2>

<div align="center">
  <img width="100%" alt="image" src="https://github.com/user-attachments/assets/12ed750b-8756-450f-b1c6-88379e6bef48" />

  <br />

  
  <img width="33%" alt="image" src="https://github.com/user-attachments/assets/e78a7c4e-bb9a-4d2d-8fc7-38a570013e69" />
  <img width="33%" alt="image" src="https://github.com/user-attachments/assets/72cf676c-f16f-41c2-9a64-972463475e0a" />
  <img width="33%" alt="image" src="https://github.com/user-attachments/assets/cd18b438-b5a4-4e29-b551-0e76412ebc54" />


</div>

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis/master/Emojis/Objects/Package.png" alt="Package" width="32" height="32" /></sub> Installation</h2>

### Quick Install

Run the automated installer:

```bash
git clone https://github.com/versenilvis/Ambxst.git ~/.config/Ambxst
cd ~/.config/Ambxst
./install.sh
```

Or run directly via curl:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/versenilvis/Ambxst/main/install.sh)
```

### What does the installer do?

1. Detects your distribution (Arch, Fedora, Debian/Ubuntu, openSUSE, NixOS).
2. Installs required system tools and libraries (Hyprland, QuickShell, Rust/Cargo, pamixer, cliphist, hyprpicker, hypridle, hyprlock, grimblast).
3. Compiles the high performance Rust backend daemon (`ambxst-daemon`) located in `ambxst-daemon/`.
4. Creates executable symlinks for `ambxst` in `~/.local/bin` and `/usr/local/bin`.
5. Prepares configuration directories in `~/.config/Ambxst`.

### Requirements

* [QuickShell](https://github.com/quickshell-mirror/quickshell)
* [Hyprland](https://hyprland.org)
* [Rust & Cargo](https://www.rust-lang.org/) (for compiling `ambxst-daemon`)
* Fonts: `Inter`, `JetBrainsMono Nerd Font`

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Telegram-Animated-Emojis/main/Objects/Keyboard.webp" alt="Keyboard" width="32" height="32" /></sub> Keybindings & Shortcuts</h2>

### Ambxst Shell Shortcuts

Configurable via `~/.config/Ambxst/binds.json` or through the Ambxst settings UI.

| Shortcut | Module | Description |
|---|---|---|
| `Super` (tap) | Command Palette / Launcher | Open app launcher and command palette |
| `Super + V` | Clipboard Manager | Open clipboard history with instant search |
| `Super + .` | Emoji Picker | Open emoji picker and copy directly |
| `Super + N` | Quick Notes | Open scratchpad and markdown notes |
| `Super + ,` | Wallpaper Selector | Browse and switch desktop wallpapers |
| `Super + Shift + C` | Settings Panel | Open Ambxst shell settings |
| `Super + Shift + A` | Google Lens | Visual search on screen crop |
| `Super + Shift + R` | Screen Recorder | Record screen region with audio toggle |
| `Super + Escape` | Power Menu | Lock, reboot, suspend, or shutdown |
| `Ctrl + Escape` | Pin Top Bar | Toggle top bar pin / auto-hide mode |
| `Alt + Tab` | Window Overview | Workspace window overview switcher |
| `Super + Alt + B` | Reload Shell | Reload Ambxst UI and restart daemon |
| `Super + Ctrl + Alt + B` | Quit Shell | Terminate Ambxst session |

### Hyprland Integration (`hyprland.lua`)

Default bindings configured in `hyprland.lua`:

| Shortcut | Action | Description |
|---|---|---|
| `Super + T` | Terminal | Launch ghostty terminal |
| `Super + B` | Browser | Launch browser |
| `Super + F` | File Manager | Launch strata file manager |
| `Super + C` | Code Editor | Launch Antigravity editor |
| `Super + Space` | Vicinae | Toggle Vicinae launcher |
| `Super + Q` | Close Window | Close current focused window |
| `Super + W` | Toggle Float | Center and float window at 70%x75% |
| `Super + M` | Exit | Exit Hyprland session |
| `Super + E` | Notifications | Toggle Ambxst notification center |
| `Super + P` | Color Picker | Hyprpicker copy hex color code |
| `Super + L` | Lock Screen | Lock session via hyprlock |
| `Super + S` | Screenshot Tool | Ambxst interactive area capture |
| `Print` | Full Screenshot | Save and copy fullscreen via grimblast |
| `Super + Print` | Active Screenshot | Save and copy active window via grimblast |
| `Super + 1..0` | Switch Workspace | Switch to workspace 1 to 10 |
| `Super + Shift + 1..0` | Move Workspace | Move focused window to workspace 1 to 10 |
| `Super + Scroll` | Cycle Workspaces | Cycle through workspaces |
| `Super + Mouse Left` | Move Window | Drag floating window |
| `Super + Mouse Right` | Resize Window | Resize window |
| `Super + Shift + Arrows`| Resize Step | Precise window resizing |

### Audio & Brightness Keys

| Key | Action |
|---|---|
| `XF86AudioRaiseVolume` | Increase master volume |
| `XF86AudioLowerVolume` | Decrease master volume |
| `XF86AudioMute` | Toggle audio mute |
| `XF86AudioMicMute` | Toggle microphone mute |
| `XF86AudioPlay` | Play / Pause active media player |
| `XF86AudioNext` | Next media track |
| `XF86AudioPrev` | Previous media track |
| `XF86MonBrightnessUp` | Increase display brightness (+5%) |
| `XF86MonBrightnessDown` | Decrease display brightness (-5%) |

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Telegram-Animated-Emojis/main/Objects/Magnifying%20Glass%20Tilted%20Left.webp" alt="Search" width="32" height="32" /></sub> Command Palette Prefixes</h2>

When opening the launcher with `Super`, type these prefixes followed by a space to jump instantly into tabs:

* `cc ` or `clip `: Switch directly to Clipboard History
* `ee ` or `emoji `: Switch directly to Emoji Picker
* `settings `, `setting `, or `config `: Open Ambxst Settings
* `audio `, `sound `, or `vol `: Open Audio mixer and volume controls
* `nn `: Switch directly to Quick Notes

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis/master/Emojis/Objects/Hammer%20and%20Wrench.png" alt="CLI" width="32" height="32" /></sub> CLI Usage (`ambxst`)</h2>

Ambxst provides a fast CLI tool to control the shell, daemon, and system via IPC:

```bash
# Launch Ambxst
ambxst

# Fast IPC trigger for specific modules
ambxst run dashboard-widgets     # Launcher
ambxst run dashboard-clipboard   # Clipboard history
ambxst run dashboard-emoji       # Emoji picker
ambxst run dashboard-notes       # Notes
ambxst run notifications         # Notification center
ambxst run powermenu             # Power menu
ambxst run overview              # Window overview
ambxst run screenshot            # Screenshot tool
ambxst run screenrecord          # Screen recorder
ambxst run lens                  # Google Lens search
ambxst run toggle-bar            # Toggle top bar pin

# System controls
ambxst lock                      # Lock screen
ambxst screen on|off             # Turn display on/off via DPMS
ambxst suspend                   # Suspend system

# Brightness management
ambxst brightness 75             # Set brightness to 75%
ambxst brightness +10            # Increase brightness by 10%
ambxst brightness -5 HDMI-A-1    # Decrease HDMI-A-1 by 5%
ambxst brightness -s             # Save current brightness
ambxst brightness -r             # Restore saved brightness
ambxst brightness -l             # List monitors

# Lifecycle
ambxst reload                    # Restart shell and daemon
ambxst quit                      # Stop Ambxst
ambxst update                    # Pull git changes and recompile ambxst-daemon
```

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Telegram-Animated-Emojis/main/Activity/Sparkles.webp" alt="Sparkles" width="32" height="32" /></sub> Features</h2>

* [x] Fast Rust daemon backend (`ambxst-daemon`) with SQLite clipboard indexing
* [x] Customizable UI components & themes
* [x] Deep Hyprland desktop integration
* [x] Command palette & app launcher
* [x] Clipboard manager with instant search
* [x] Quick markdown notes
* [x] Wallpaper switcher
* [x] Emoji picker
* [x] System monitor & resource graphs
* [x] Media controller with MPRIS
* [x] Notification center
* [x] Wi-Fi & Bluetooth management
* [x] Audio mixer & EasyEffects integration
* [x] Screen capture & screen recording
* [x] Google Lens visual search
* [x] Color picker
* [x] Power menu & lockscreen
* [x] Multi-monitor support & per-monitor brightness control

---

<h2><sub><img src="https://raw.githubusercontent.com/Tarikul-Islam-Anik/Animated-Fluent-Emojis/master/Emojis/Smilies/Alien%20Monster.png" alt="Alien Monster" width="32" height="32" /></sub> Configuration & Architecture</h2>

All user configurations are stored under `~/.config/Ambxst`:

* `config/`: JSON configuration files for themes, bar, dock, notch, workspaces, system, and performance.
* `binds.json`: User keybinding mappings.
* `ambxst-daemon`: Standalone Rust daemon handling clipboard history (SQLite), hardware brightness control, system telemetry, and IPC pipe synchronization.

To customize keybindings, edit `~/.config/Ambxst/binds.json` or open the settings UI (`Super + Shift + C`).
