# Linux support

`install.sh` already detects Linux (`uname -s == Linux`) and routes to
`apt`, `dnf`, or `pacman` based on what's on `$PATH`. To finish Linux
support, populate the package lists in this directory:

- `packages.apt.txt` — Debian / Ubuntu (`apt-get install -y ...`)
- `packages.dnf.txt` — Fedora / RHEL family (`dnf install -y ...`)
- `packages.pacman.txt` — Arch family (`pacman -S --noconfirm --needed ...`)

One package per line, comment lines (starting with `#`) are tolerated by
the `xargs` invocation as long as you keep them short. See
`packages.apt.txt` for a starter list.

Still to do for full Linux parity:
- A Ghostty install path (it's available as a `.deb`, `.rpm`, or build
  from source — pick one and add a function in `install.sh`).
- Replace `apply_os_defaults` for Linux: GNOME / KDE settings via
  `gsettings` / `kwriteconfig5`, or skip entirely.
- Decide on a font install path (Nerd Fonts via `apt`/`dnf` package or
  fc-cache).
