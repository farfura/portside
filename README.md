# Portside

A native macOS menu bar app that keeps an eye on your local dev world.

**Ports.** Every dev server listening on your Mac, live, with the framework detected (Next.js, Vite, NestJS, Rails, Django, Postgres, Redis, Docker containers and more), the project it belongs to and a health dot.

**Find a port.** Search by port number (`3000`, `:30`) or by project, folder, container or framework name. Search covers system ports too, and tells you when a port is free.

**Port superpowers.**
* **Open on phone.** A QR code for any port. If the server only listens on localhost, Portside relays it to your local network on the fly (3000 becomes 13000), with no config change.
* **Share publicly.** One click gives you an HTTPS link through a free Cloudflare quick tunnel. No account needed.
* **Traffic Inspector.** Every request through the public link is recorded: method, path, status, timing, headers and pretty printed bodies. Replay any request against localhost with one click, or copy it as cURL. Perfect for webhooks.
* **Health and history.** Status code and latency per server, plus a "Recently stopped" list so you notice when something crashed.
* **Stop, open, reveal.** Kill a process (click twice to confirm), open it in the browser, or jump to the project in your editor, terminal or Finder.

**Docker.** Every container, running or stopped, grouped by compose project, with its published ports (click to open), image, status and health color. Start, stop, restart or resume a container, open the compose folder in your editor or terminal, or copy its logs and shell commands. If the engine isn't running, Portside offers to start Docker Desktop, OrbStack, Colima or Rancher Desktop.

**Repo Radar.** Scans your code folders and shows which repos need you: uncommitted changes, commits not pushed, branches never published, branches behind their remote, stashes and conflicts. A project made of several repos (a folder with `frontend` and `backend` repos side by side, or repos nested inside another repo) is shown as one project with its repos underneath. Fetch all remotes in one click, and open any repo in your editor, terminal, Finder or on GitHub.

## Download

The current public build is [Portside 1.1.0](https://github.com/farfura/portside/releases/latest). Open the `.dmg` and drag Portside into Applications.

If a copy is already running, quit it from the panel before you open the new one. macOS keeps the old menu bar app in memory when you replace the file, so the sailboat keeps showing the previous version until you quit it.

This build is for Apple Silicon (M-series Macs) on macOS 14 or newer. It is not notarized. The first time you open it, right-click Portside and choose Open. If macOS still blocks it, allow it in System Settings → Privacy & Security.

## Requirements

* macOS 14 Sonoma or newer
* Xcode 15+ or the Command Line Tools (`xcode-select --install`)
* For public links: `cloudflared` (Portside can install it for you through Homebrew)

## Build and run

```bash
cd Portside
chmod +x build.sh
./build.sh --install
```

That compiles a release build, wraps it into `Portside.app`, copies it to `/Applications` and launches it. Look for the sailboat in your menu bar.

To only build: `./build.sh`, then `open build/Portside.app`.

To hack on it in Xcode: `open Package.swift`, pick the Portside scheme and run.

## First launch

1. Click the sailboat. The Ports tab fills in within a second.
2. Open **Repo Radar**. By default Portside scans your home folder three levels deep, skipping Desktop, Documents, Downloads and Library. Add those, or any other folder, in Settings with **Add folder**.
3. In Settings, pick the editor and terminal you want for the open buttons.
4. Turn on **Launch at login** once the app lives in `/Applications`.

macOS may ask to allow incoming connections the first time you use **Open on phone**. Allow it, since that's the relay your phone connects to.

## Shortcuts (inside the panel)

* `⌘R` refresh everything
* `⌘,` settings
* `⌘[` or `Esc` go back

## How it works

* Ports come from `lsof` (listening TCP sockets for your user), enriched with `ps` for the command line and the process working directory to find the project's git root. Docker ports are mapped to container names through `docker ps`.
* The Docker tab runs `docker ps -a` every few seconds while the panel is open (every 30 seconds otherwise).
* Health checks are a single `HEAD /` when a server first appears and when you open the panel, so your dev server logs don't get spammed.
* The phone relay is a small TCP forwarder built on Network.framework.
* Public sharing runs `cloudflared tunnel --url` pointed at a tiny inspecting reverse proxy inside Portside, which then forwards to your server. The proxy rewrites the Host header to `localhost:PORT`, so Vite and webpack host checks pass, and sets `X-Forwarded-Host` and `X-Forwarded-Proto`. WebSocket upgrades (HMR) are piped straight through.
* Repo Radar uses `git status --porcelain=v2 --branch --show-stash` with `GIT_OPTIONAL_LOCKS=0`, so it never fights your own git commands for the index lock.

## Notes

* Streaming responses (server sent events) are forwarded as they arrive, but the inspector shows the body only after the response ends. Bodies over 2 MB are truncated in the log, never in the actual response.
* Quick tunnel links are temporary and change each time you share.
* Desktop, Documents and Downloads aren't scanned by default, because touching them triggers a macOS privacy prompt. Add them in Settings if your code lives there.

## Project layout

```
Sources/Portside/
  App/    PortsideApp (menu bar + inspector window), Settings, launchers, toasts, QR
  Core/   PortScanner, PortStore, Docker, LANBridge + PipePair, InspectingProxy, TunnelSession, HTTP, Repos, Shell
  UI/     Theme and components, RootView, PortsView, DockerView, PortDetailView, ReposView, SettingsView, TrafficWindow
Resources/ Info.plist, AppIcon.png
build.sh   builds the .app bundle
```
