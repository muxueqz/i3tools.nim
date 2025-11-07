Nim i3 Tools
============

A lightweight set of command-line utilities written in **Nim** for controlling **i3** and **Sway** window managers.  
This toolkit provides fast, scriptable commands to select windows, switch workspaces, and generate custom status outputs — all from your terminal.

---

🚀 Features
----------

* 🪟 **Window Selection** – Focus or select windows interactively.
* 🖥️ **Workspace Switching** – Quickly jump between workspaces.
* 📊 **Custom Status Output** – Generate and extend i3/Sway status bar data.
* ⚡ **Fast & Minimal** – Compiled Nim binary with zero runtime dependencies.

---

🧩 Installation
--------------

### Requirements

* [Nim compiler](https://nim-lang.org/install.html) (≥ 1.6 recommended)
* [i3](https://i3wm.org/) **or** [Sway](https://swaywm.org/)

### Build

```
git clone https://github.com/muxueqz/i3tools.nim.git
cd i3tools.nim
nim c -d:release i3tools.nim

```

This will create an executable named `i3tools`.

---

⚙️ Usage
--------

Run `i3tools` followed by a command and optional arguments:

```
i3tools <command> [options...]

```

### Available Commands

| Command | Description |
| --- | --- |
| `select-window` | Select or focus a window interactively. |
| `switch-workspace` | Switch to the specified workspace. |
| `i3status` | Generate custom status output for i3/Sway bars. |

### Examples

```
# Select a window
i3tools select-window

# Switch to workspace 2
i3tools switch-workspace 2

# Print custom status output
i3tools i3status

```

If no command is given, the tool exits with a non-zero status.

---

🪄 Integrating with Sway (or i3)
-------------------------------

You can easily integrate `i3tools` into your **Sway** or **i3** configuration to enhance workflow and customize your bar.

### Example Configuration

```
# Define the path to the tool
set $i3tools [i3tools.nim]/i3tools

# Window selection
bindsym $mod+f exec --no-startup-id $i3tools select-window current_workspace
bindsym $mod+Shift+f exec --no-startup-id $i3tools select-window

# Workspace switching
bindsym $mod+1 exec --no-startup-id $i3tools switch-workspace $ws1
bindsym $mod+2 exec --no-startup-id $i3tools switch-workspace $ws2
bindsym $mod+3 exec --no-startup-id $i3tools switch-workspace $ws3
bindsym $mod+4 exec --no-startup-id $i3tools switch-workspace $ws4
bindsym $mod+5 exec --no-startup-id $i3tools switch-workspace $ws5
bindsym $mod+6 exec --no-startup-id $i3tools switch-workspace $ws6
bindsym $mod+7 exec --no-startup-id $i3tools switch-workspace $ws7
bindsym $mod+8 exec --no-startup-id $i3tools switch-workspace $ws8

# Custom status bar integration
bar {
    status_command $i3tools i3status
    position top
    tray_output *
}

```

### Notes

* Replace `[i3tools.nim]/i3tools` with the **actual path** to your compiled binary (e.g. `/usr/local/bin/i3tools` or `~/bin/i3tools`).
* The `current_workspace` argument limits selection to windows in the active workspace.
* The `i3tools i3status` command can be extended to show system info, weather, or custom scripts.
---

🧠 Compatibility
---------------

✅ Works with both **i3** and **Sway** window managers.  

---

🧰 Contributing
--------------

Contributions are welcome!  
To contribute:

1. Fork the repository
2. Create a new branch (`git checkout -b feature-name`)
3. Commit your changes
4. Open a Pull Request

---

📝 License
---------

This project is licensed under the **GPLv2 License**.  
See LICENSE for details.
