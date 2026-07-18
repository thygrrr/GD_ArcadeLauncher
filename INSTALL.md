# Installation Guide - c-base Arcade Launcher

Complete step-by-step installation guide for Ubuntu Linux.

## Prerequisites

- Fresh Ubuntu installation (20.04 LTS or newer recommended)
- Physical access to the machine (for initial setup)
- SSH access for remote administration

## Step 1: Session Type (Wayland)

The cabinet runs the default Ubuntu **Wayland** session — no changes needed.
The launcher must run as a systemd *user* service inside the session
(Step 8, Variant A) to reach the compositor.

```bash
echo $XDG_SESSION_TYPE   # → wayland
```

Godot logging `X11 Display is not available … falling back to wayland` at
startup is expected and harmless.

## Step 2: Create Arcade User

Create a dedicated user for the arcade launcher:

```bash
# Create user without password prompt (will set up auto-login)
sudo adduser --disabled-password --gecos "Arcade User" arcade

# Add to video and audio groups
sudo usermod -aG video,audio arcade
```

## Step 3: Configure Auto-Login

Configure GDM to automatically log in as the arcade user:

```bash
sudo nano /etc/gdm3/custom.conf
```

Add these lines in the `[daemon]` section:

```ini
AutomaticLoginEnable = true
AutomaticLogin = arcade
```

Save and exit.

## Step 4: Create Directory Structure

```bash
# Create main arcade directory structure
sudo mkdir -p /arcade/{launcher,games,scores,logs,tools,media}

# Create media subdirectories
sudo mkdir -p /arcade/media/{sounds,fonts,shaders}

# Set ownership to arcade user
sudo chown -R arcade:arcade /arcade

# Set proper permissions
sudo chmod -R 755 /arcade
sudo chmod 775 /arcade/games  # Allow uploads
sudo chmod 775 /arcade/scores # Allow score updates
```

## Step 5: Install Required Packages

```bash
# Update package list
sudo apt-get update

# Install inotify-tools for file watching
sudo apt-get install -y inotify-tools

# Optional: Install OpenSSH server for remote access
sudo apt-get install -y openssh-server

# Optional: Install utilities
sudo apt-get install -y htop curl wget
```

## Step 6: Export Launcher from Godot

On your development machine:

1. Open the project in Godot 4.5
2. Go to **Project → Export**
3. Add a new **Linux/X11** export preset if not present
4. Configure export settings:
   - **Name:** `c-base Arcade Launcher`
   - **Runnable:** ✓ (checked)
   - **Export Path:** `builds/linux/launcher.x86_64`
   - **Resources → Export Mode:** Export all resources in the project
   - **Binary Format → 64 bits:** ✓ (checked)
5. Click **Export Project**

This will create:
- `launcher.x86_64` (executable)
- `launcher.pck` (data file)

## Step 7: Upload Launcher to Cabinet

From your development machine:

```bash
# Upload launcher files
scp builds/linux/launcher.x86_64 arcade@<cabinet-ip>:/arcade/launcher/
scp builds/linux/launcher.pck arcade@<cabinet-ip>:/arcade/launcher/

# Upload watcher script
scp tools/watch_games.sh arcade@<cabinet-ip>:/arcade/tools/

# Make executable
ssh arcade@<cabinet-ip> "chmod +x /arcade/launcher/launcher.x86_64"
ssh arcade@<cabinet-ip> "chmod +x /arcade/tools/watch_games.sh"
```

## Step 8: Install Systemd Services

**Variant A (recommended): user services owned by the desktop user** (the
auto-login account). They start with the session, inherit its display
environment, and stop with it.

```bash
# As the desktop user (the one GDM auto-logs in) on the cabinet:
mkdir -p ~/.config/systemd/user
cp install/systemd/user/arcade-launcher.service ~/.config/systemd/user/
cp install/systemd/user/arcade-watch.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable arcade-launcher.service arcade-watch.service
systemctl --user start arcade-launcher.service arcade-watch.service

# Check status / logs:
systemctl --user status arcade-launcher.service
journalctl --user -u arcade-launcher.service -f
```

The desktop user needs access to the launcher's files:

```bash
# Read/execute for launcher + games, write for scores and state
sudo chown -R <desktop_user>: /arcade
# (If a separate SFTP upload user writes /arcade/games, use a shared group
# on that directory instead of exclusive ownership.)
```

**Variant B: system services** (legacy X11 setup — not suitable for the
Wayland cabinet):

```bash
# Copy service files to systemd directory
sudo cp install/systemd/arcade-launcher.service /etc/systemd/system/
sudo cp install/systemd/arcade-watch.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services to start on boot
sudo systemctl enable arcade-launcher.service
sudo systemctl enable arcade-watch.service

# Start services now (optional, or reboot)
sudo systemctl start arcade-launcher.service
sudo systemctl start arcade-watch.service
```

Check service status:

```bash
sudo systemctl status arcade-launcher.service
sudo systemctl status arcade-watch.service
```

View logs:

```bash
# Launcher logs
sudo journalctl -u arcade-launcher.service -f

# Watcher logs
sudo journalctl -u arcade-watch.service -f
```

## Step 9: Configure SFTP Access for Game Uploads

### Option A: Simple (arcade user with password)

```bash
# Set a password for arcade user
sudo passwd arcade
```

Users can now upload via SFTP:
```bash
sftp arcade@<cabinet-ip>
cd /arcade/games
put -r my_game_folder/
```

### Option B: Secure (dedicated upload user with chroot)

Create a restricted user for uploads only:

```bash
# Create upload user
sudo adduser --disabled-password --gecos "Arcade Upload" arcade_upload

# Add to arcade group
sudo usermod -aG arcade arcade_upload

# Set password
sudo passwd arcade_upload
```

Configure SSH for SFTP-only chroot access:

```bash
sudo nano /etc/ssh/sshd_config
```

Add at the end:

```
Match User arcade_upload
    ForceCommand internal-sftp
    ChrootDirectory /arcade/games
    PermitTunnel no
    AllowAgentForwarding no
    AllowTcpForwarding no
    X11Forwarding no
```

Fix permissions for chroot:

```bash
sudo chown root:root /arcade/games
sudo chmod 755 /arcade/games
```

Restart SSH:

```bash
sudo systemctl restart ssh
```

## Step 10: Test Installation

1. **Reboot the cabinet:**
   ```bash
   sudo reboot
   ```

2. **Verify auto-login:** The system should boot directly to the launcher in fullscreen.

3. **Test game upload:**
   ```bash
   # From another machine
   sftp arcade@<cabinet-ip>
   cd /arcade/games
   mkdir test_game
   cd test_game
   # Upload game files
   ```

4. **Verify live refresh:** The game should appear in the launcher list within 1-2 seconds.

## Step 11: Upload Your First Game

See [GAME_SPEC.md](GAME_SPEC.md) for complete game requirements.

Minimal test game structure:
```
/arcade/games/my_game/
├── game.x86_64        # Linux executable
├── game.pck           # Godot pack
├── game.json          # Metadata (optional)
├── screenshot.png     # Preview image (optional)
└── icon.png          # List icon (optional)
```

Example `game.json`:
```json
{
  "title": "Space Invaders Clone",
  "author": "Your Name",
  "description": "Classic space shooter with modern graphics",
  "players": 2,
  "year": 2024
}
```

## Troubleshooting

### Launcher doesn't start on boot

```bash
# Check service status
sudo systemctl status arcade-launcher.service

# Check logs
sudo journalctl -u arcade-launcher.service -n 50

# Common issues:
# - DISPLAY environment variable not set
# - X11 not running
# - Missing dependencies
```

### Games don't appear in list

```bash
# Check games directory permissions
ls -la /arcade/games

# Check watcher service
sudo systemctl status arcade-watch.service

# Manually trigger event
echo "games_changed" > /tmp/arcade_event
```

### Game won't launch

- Ensure executable has +x permission: `chmod +x /arcade/games/my_game/game.x86_64`
- Verify game is built for Linux x86_64
- Check launcher logs: `sudo journalctl -u arcade-launcher.service -f`

### Launcher logs "X11 Display is not available" / falls back to Wayland

**This is expected and harmless** — the cabinet runs a Wayland session
(Step 1). Godot tries the x11 driver first, then falls back to Wayland,
which is where it's supposed to land.

What actually matters is that the launcher runs as a **user service inside
the graphical session** (Step 8, Variant A) so `WAYLAND_DISPLAY` and
`XDG_RUNTIME_DIR` are inherited. If the launcher aborts with *no* usable
display at all, check:

```bash
systemctl --user show-environment | grep -E "WAYLAND_DISPLAY|DISPLAY|XDG_RUNTIME_DIR"
# WAYLAND_DISPLAY should be set (usually wayland-0)
```

### Display issues

```bash
# Check X11 session
echo $XDG_SESSION_TYPE  # Should be "x11"
echo $DISPLAY           # Should be ":0" or ":1"

# Test X11
DISPLAY=:0 xrandr      # Should show display info
```

### Remote access issues

```bash
# Check SSH service
sudo systemctl status ssh

# Check firewall
sudo ufw status
sudo ufw allow ssh
```

## Maintenance

### Update launcher

```bash
# Stop service
sudo systemctl stop arcade-launcher.service

# Upload new version
scp launcher.x86_64 launcher.pck arcade@<cabinet-ip>:/arcade/launcher/

# Restart service
sudo systemctl start arcade-launcher.service
```

### View logs

```bash
# Live launcher logs
sudo journalctl -u arcade-launcher.service -f

# Live watcher logs
sudo journalctl -u arcade-watch.service -f

# System logs
tail -f /arcade/logs/launcher.log  # If implemented
```

### Restart services

```bash
# Restart launcher
sudo systemctl restart arcade-launcher.service

# Restart watcher
sudo systemctl restart arcade-watch.service

# Restart both
sudo systemctl restart arcade-launcher.service arcade-watch.service
```

## Security Considerations

1. **Firewall:** Configure UFW to only allow SSH
   ```bash
   sudo ufw enable
   sudo ufw allow ssh
   ```

2. **SSH keys:** Use SSH key authentication instead of passwords
   ```bash
   ssh-copy-id arcade@<cabinet-ip>
   ```

3. **Updates:** Keep system updated
   ```bash
   sudo apt-get update && sudo apt-get upgrade
   ```

4. **Backups:** Regularly backup `/arcade/scores` and `/arcade/games`

## Optional Enhancements

### Disable desktop environment features

Edit `/home/arcade/.profile` to disable screensaver, power management, etc.:

```bash
# Disable screen blanking
xset s off
xset -dpms
xset s noblank
```

### Add startup sound

Add to `/home/arcade/.bashrc`:

```bash
if [ "$XDG_SESSION_TYPE" = "x11" ]; then
    aplay /arcade/media/sounds/startup.wav &
fi
```

### Set up monitoring

Install monitoring tools to track cabinet health:

```bash
sudo apt-get install prometheus-node-exporter
```

## Next Steps

- Upload games following [GAME_SPEC.md](GAME_SPEC.md)
- Customize theme and graphics
- Add custom boot sound and UI sounds
- Set up backup schedule for scores
- Configure remote monitoring

## Support

For issues or questions:
- Check the troubleshooting section above
- Review logs: `sudo journalctl -u arcade-launcher.service`
- Report issues on GitHub: [repository URL]
