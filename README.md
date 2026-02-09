#Palworld Server Manager


A fully‑featured, real‑time management dashboard for Palworld Dedicated Servers.
Designed for Windows PowerShell with a modern GUI, live monitoring, automated restarts, in‑game announcements, backups, configuration editing, and more.

This tool is built for server owners who want a professional‑grade control panel without needing to touch command lines or raw REST API calls.

---

FEATURES

Real‑Time Monitoring
- Live CPU, RAM, FPS, and Player Count charts
- Compact 720p‑optimized layout
- Auto‑refreshing metrics from REST API
- Peak RAM tracking
- Thread & handle count display

Automated Restart System
- Fully synced 6‑hour restart timer
- Countdown based on REST uptime (no drift)
- Color‑coded warnings (yellow ≤10m, red ≤1m)
- In‑game announcements at: 1h, 30m, 15m, 10m, 9m…1m
- Clean integration with Palworld’s built‑in 30‑second shutdown banner
- Zero duplicate announcements
- Restart pipeline with safety checks

Tabs & Tools
- Server Tab: Start, Stop, Restart, Force Kill, status indicators
- Configuration Tab: Edit PalWorldSettings.ini with a GUI
- Backups Tab: Manual + automatic backups
- Players Tab: Live player list
- Monitoring Tab: Full metrics dashboard
- RCON Console Tab: Send announcements and commands directly in‑game

Modular Architecture
- Clean PowerShell modules
- Embedded WinForms UI
- External GUI embedding support
- Safe retry logic for REST API calls

Launcher Included
Just double‑click the included launcher to start the manager.

---

INSTALLATION GUIDE

1. Install the Palworld Dedicated Server (REQUIRED)
Install via Steam under Library → Tools → Palworld Dedicated Server.
Place this manager in the SAME folder as PalServer.exe.

2. Install the Server Manager
Copy all files from this repository into the Palworld server root folder.
Ensure the folder contains: Palworld_Server_Manager.ps1, Palworld_Server_Manager_Launcher.vbs, modules, UI assets.

3. Launch the Manager
Double‑click Palworld_Server_Manager_Launcher.vbs.

---

FIRST‑TIME USAGE GUIDE

1. Launch the GUI
You’ll see server status, CPU/RAM/Players, uptime, restart countdown.

2. Configure REST API settings in PalWorldSettings.ini:
[ServerSettings]
RESTAPIEnabled=True
RESTAPIPort=8212
RESTAPIKey=YOUR_KEY_HERE
AdminPassword=YOUR_ADMIN_PASSWORD

3. Start the server from the Server tab.
The manager will launch the server, detect the process, begin monitoring, and start the 6‑hour restart cycle.

4. Verify monitoring in the Monitoring tab.

5. Test announcements in the RCON Console tab.

---

AUTO‑RESTART SYSTEM

- Countdown synced to REST uptime
- Yellow warning ≤10 minutes
- Red warning ≤1 minute
- Automatic announcements at major intervals
- Countdown stops at 30 seconds so Palworld’s built‑in shutdown banner takes over

---

TROUBLESHOOTING

Monitoring not updating: Check REST API settings and firewall.
Server not starting: Ensure manager is in the same folder as PalServer.exe.
Announcements not appearing: Verify AdminPassword and RESTAPIKey.

---

CREDITS
Created by DarkJesus
Built with help from Microsoft Copilot
