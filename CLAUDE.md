# CLAUDE.md

## Purpose

This project builds a qcow2 disk image (Ubuntu 24.04) ready to upload to OpenStack Glance. The image runs nginx and serves a single-page demo that displays live server and client network information.

## Requirements

```bash
sudo apt install qemu-utils libguestfs-tools qemu-system-x86 wget
```

| Tool | Used for |
|------|----------|
| `qemu-img` | Convert, resize, sparsify the image |
| `virt-customize` | Install packages and copy files into the image |
| `virt-sysprep` | Seal the image before distribution |
| `virt-sparsify` | Reclaim unused blocks |
| `wget` | Download the Ubuntu cloud base image |
| `qemu-system-x86_64` | Local test boot |

## Build

```bash
make          # produces openstack-demo.qcow2 (~4 GB)
make clean    # removes the image
```

`make` downloads the Ubuntu 24.04 cloud image on first run (~600 MB, cached in `~/.cache/ubuntu-cloud-images/`). Subsequent builds reuse the cache. **Requires `sudo`** — libguestfs (virt-customize, virt-sysprep) needs read access to `/boot/vmlinuz-*`.

Build variables (override on the command line):

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE`  | `openstack-demo.qcow2` | Output filename |
| `SIZE`   | `4G` | Disk size |
| `ROOTPW` | `demo` | Root password injected into the image |

## Build pipeline (internals)

`qemu-img convert` → `qemu-img resize` → `virt-customize` → `virt-sysprep` → `virt-sparsify`

**Ubuntu 24.04 cloud image partition layout:** `sda1` = root, `sda14` = BIOS boot, `sda15` = EFI, `sda16` = /boot. Expand `sda1` with `growpart /dev/sda 1`.

**Do not use `virt-builder`** — Ubuntu 24.04 is not available (max: 20.04). Use wget + cloud image instead.

**Do not run `sgdisk` on the qcow2 file** — it expects raw format and corrupts the image. GPT backup header is fixed by `growpart` inside virt-customize.

**cloud-init must stay enabled** — it handles network interface naming (ens3, etc.) and DHCP on first boot in OpenStack. Root login is enabled via `/etc/cloud/cloud.cfg.d/99-root.cfg`.

## Local preview

```bash
./preview.sh          # serves web/ on port 8080 and opens the browser
PORT=3000 ./preview.sh  # custom port
```

Starts a Python mock server that mimics the nginx `/info` endpoint and opens the browser. Ctrl+C cleanly stops the server.

## Local test with the built image

```bash
qemu-system-x86_64 -m 512 -drive file=openstack-demo.qcow2,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::8080-:80 -device virtio-net,netdev=net0 \
  -nographic
```

Then open `http://localhost:8080`. Login: `root` / `demo`.

## Architecture

```
web/index.html   Single-file frontend (HTML + CSS + JS, no build step)
nginx/default    nginx vhost config, deployed to /etc/nginx/sites-available/default
Makefile         Drives qemu-img + virt-customize to produce the qcow2
preview.sh       Local dev server — serves web/ and mocks the /info endpoint
README.md        End-user documentation
```

### How server data reaches the browser

nginx exposes a `/info` endpoint that uses built-in variables to return a JSON object — no backend process required:

```json
{
  "client_ip":   "$remote_addr",
  "server_addr": "$server_addr",
  "server_port": "$server_port",
  "hostname":    "$hostname",
  "request_uri": "$request_uri"
}
```

The page's JavaScript fetches this endpoint on load and on every auto-refresh cycle (configurable: 5 / 10 / 30 / 60 s), then populates the info cards without a full page reload.

### Frontend design

`web/index.html` is self-contained — no bundler, no external JS dependencies. Google Fonts (`Instrument Sans` + `IBM Plex Mono`) are loaded via CDN; the page degrades gracefully to system fonts when offline. On first load, theme is detected from `prefers-color-scheme` (defaults to light if undetectable); manual override is stored in `localStorage`.

## Upload to OpenStack

```bash
openstack image create \
  --file openstack-demo.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  openstack-demo
```
