# VM-Clean up
VM-Cleanup is a one script tool that cleans up any Kali-Based virtual machine! It removes unnecessary files, trims caches and logs, frees up space so you can keep your virtual machine nice and compact.
This works on VirtualBox and Virtual machine

## Features: 
**APT cleanup** — Removes old packages, caches, and residual configs  
- **Chromium removal** — Cleans Chromium and related cache  
- **Brave browser trim** — Deletes cache, keeps your profile and bookmarks  
- **Log + journal cleanup** — Keeps only the last N days (default 7)  
- **Temporary file cleanup** — Clears `/tmp`, `~/.cache`, and other system temp files  
- **Optional ecosystem pruning**:
  - `--include-docker` → Remove stopped containers, unused images/volumes  
  - `--include-snap` → Remove old Snap revisions  
  - `--include-flatpak` → Uninstall unused Flatpak runtimes  
- **Zero-fill option** — Overwrites free space with zeroes to improve VM compacting  
- **Fully safe defaults** — All destructive actions are limited to temp/cache space

## Usage 

### 1. Clone or download
```bash
git clone https://github.com/404Yeti/virtualmachine-cleanup-script/blob/main/vm-cleanup.sh
cd vm-cleanup
chmod +x vm-cleanup.sh
sudo ./tlvm-clean.sh
