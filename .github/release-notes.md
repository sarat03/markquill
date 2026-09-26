A small, fast Markdown viewer and editor for macOS, Windows and Linux.

## Download

| OS | File |
|---|---|
| macOS, Apple silicon (M1 and later) | `MarkQuill_*_mac_m_arm.dmg` |
| macOS, Intel | `MarkQuill_*_mac_intelx64.dmg` |
| Windows 10/11, x64 | `MarkQuill_*_win-x64-setup.exe` (or the `.msi`) |
| Windows 11, ARM | `MarkQuill_*_win-arm-setup.exe` |
| Linux: Debian 12+, Ubuntu 22.04+, Mint 21+ | `MarkQuill_*_amd64.deb` |
| Linux: Fedora | `MarkQuill-*.x86_64.rpm` |

Or install from the command line: `brew install --cask markquill` after `brew tap sarat03/markquill https://github.com/sarat03/markquill` on macOS, `winget install Sarat.MarkQuill` on Windows (coming soon). The [README](https://github.com/sarat03/markquill#download) has the Linux one-liners.

## First launch

The installers aren't code-signed yet, so your OS warns you the first time:

- **macOS:** open the `.dmg` and drag MarkQuill to Applications. Open it once; macOS blocks it. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. If macOS says the app "is damaged", run `xattr -dr com.apple.quarantine /Applications/MarkQuill.app` in Terminal.
- **Windows:** on the SmartScreen prompt, click **More info** → **Run anyway**.
- **Linux:** `sudo apt install ./MarkQuill_*.deb` or `sudo dnf install ./MarkQuill-*.rpm`.

Features, shortcuts and build instructions are in the [README](https://github.com/sarat03/markquill#readme).
