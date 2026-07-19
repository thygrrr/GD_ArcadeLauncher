#!/usr/bin/env nu
# Deploy the exported launcher build to the arcade cabinet.
# Run: nu tools/deploy_launcher.nu
# Nushell port of deploy_launcher.sh — keep the two in sync.
#
# Single SSH connection: both files are streamed through stdin via tar,
# extracted to a temp dir, then renamed into place (a rename avoids the
# "Text file busy" error you get overwriting a running binary in place).

def main [] {
    let host = ($env.ARCADE_HOST? | default "alien@172.31.78.116")
    let project_dir = ($env.FILE_PWD | path join ".." | path expand)
    let build_dir = ($project_dir | path join "build")
    mkdir $build_dir

    # Export the Linux build first (preset "Linux" in export_presets.cfg).
    let godot = ($env.GODOT_EDITOR? | default "godot")
    print $">> Exporting Linux build with ($godot)"
    let export = (do { ^$godot --headless --path $project_dir --export-release "Linux" ($build_dir | path join "launcher.x86_64") } | complete)
    if $export.exit_code != 0 {
        print $export.stdout
        print $export.stderr
        error make {msg: "Godot export failed — is GODOT_EDITOR set and the Linux export template installed?"}
    }

    for f in ["launcher.x86_64" "launcher.pck"] {
        if not ($build_dir | path join $f | path exists) {
            error make {msg: $"Missing ($build_dir | path join $f) — export failed?"}
        }
    }

    let remote = r#'
set -e
# Binary lives in /arcade directly: exported Godot pins its CWD to the exe
# dir, so exe dir == data root keeps games/, scores/, logs/ resolving there.
D=/arcade
mkdir -p "$D/.new"
tar -xf - -C "$D/.new"
chmod +x "$D/.new/launcher.x86_64"
mv -f "$D/.new/launcher.x86_64" "$D/launcher.x86_64"
mv -f "$D/.new/launcher.pck"    "$D/launcher.pck"
rmdir "$D/.new"
echo ">> files installed in $D"
pids=$(pgrep -x launcher.x86_64 || true)
if [ -z "$pids" ]; then
    echo ">> launcher not running — nothing to restart"
elif kill $pids 2>/dev/null; then
    echo ">> launcher stopped (pid $pids); systemd will respawn it with the new build"
else
    owner=$(ps -o user= -p $(echo $pids | cut -d" " -f1))
    echo ">> WARN: cannot signal launcher pid $pids — it runs as user $owner, not $(whoami)."
    echo ">>       New build is deployed but NOT live. Restart it as that user, e.g.:"
    echo ">>       sudo systemctl restart arcade-launcher"
fi
'#

    print $">> Deploying to ($host) — single connection, one login"
    tar -C $build_dir -cf - launcher.x86_64 launcher.pck | ssh $host $remote
    print ">> Deploy complete."
}
