<div align="center">
  <img src="./Cliplet/Assets.xcassets/NimclipAppIcon.imageset/nimclip-app-icon.png" width="112" height="112" alt="Nimclip icon">
  <h1>Nimclip</h1>
  <p>Clipboard history manager for macOS</p>
  <p><a href="./README.md">简体中文</a> · <strong>English</strong></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-15.0%2B-242424?style=flat-square&logo=apple&logoColor=white" alt="macOS 15.0+">
    <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-supported-554f49?style=flat-square" alt="Apple Silicon and Intel">
    <img src="https://img.shields.io/badge/License-Apache--2.0-71685f?style=flat-square" alt="Apache License 2.0">
  </p>
</div>

<p align="center">
  <a href="./docs/images/nimclip-menu-light@2x.png"><img src="./docs/images/nimclip-menu-light@2x.png" width="420" alt="Nimclip main window in light mode"></a>
  <a href="./docs/images/nimclip-menu-dark@2x.png"><img src="./docs/images/nimclip-menu-dark@2x.png" width="420" alt="Nimclip main window in dark mode"></a>
</p>
<p align="center">
  <sub>Light and dark themes · Click an image to view the full @2x capture</sub>
</p>

## What is Nimclip?

Nimclip is a free and open-source, native, local-first clipboard history manager that lives in the macOS menu bar. Press <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> to find and paste something you copied earlier.

## Features

- History for text, links, code, images, and rich text
- Search, type filters, favorites, and tags
- Source application names and icons
- Image thumbnails and full previews
- Plain-text paste and multi-item merging
- Configurable history limits and retention periods
- Independent light and dark appearances
- Instant in-app language switching between Simplified Chinese and English
- Customizable global shortcut and launch at login

## Interface

### Image and long-text previews

Images appear as thumbnails in clipboard history and can be opened in a full preview. Long text also supports a separate, scrollable preview.

<p align="center">
  <a href="./docs/images/nimclip-image-preview-light@2x.png"><img src="./docs/images/nimclip-image-preview-light@2x.png" width="420" alt="Nimclip image preview in light mode"></a>
  <a href="./docs/images/nimclip-image-preview-dark@2x.png"><img src="./docs/images/nimclip-image-preview-dark@2x.png" width="420" alt="Nimclip image preview in dark mode"></a>
</p>

### Settings

Configure the app language, appearance, global shortcut, history limit, retention period, and launch-at-login behavior.

<p align="center">
  <a href="./docs/images/nimclip-settings-light@2x.png"><img src="./docs/images/nimclip-settings-light@2x.png" width="420" alt="Nimclip settings in light mode"></a>
  <a href="./docs/images/nimclip-settings-dark@2x.png"><img src="./docs/images/nimclip-settings-dark@2x.png" width="420" alt="Nimclip settings in dark mode"></a>
</p>

### Update notifications

Nimclip can notify you when a new version is available. Updating the app does not remove clipboard history stored on your Mac.

<p align="center">
  <a href="./docs/images/nimclip-update-notification.png"><img src="./docs/images/nimclip-update-notification.png" width="887" alt="Nimclip update notification"></a>
</p>

### About

The About page includes the version, open-source license, project home, contact options, and a Support entry. Support displays the WeChat Pay and Alipay QR codes inside Nimclip.

## Privacy and storage

Nimclip persists clipboard history locally with SwiftData and SQLite. Your history remains available after quitting the app or restarting your Mac.

- Clipboard contents stay on your Mac
- No account is required
- Clipboard contents are never uploaded
- The default retention policy is 500 items for 7 days
- Favorites are never removed automatically
- History and settings: `~/Library/Application Support/Cliplet.store`
- Images: `~/Library/Application Support/Cliplet/ClipboardImages/`

## Support

Nimclip is free and open source, and every feature remains free to use. If it helps you, you can optionally buy the author a coffee.

<table align="center">
  <tr>
    <th>WeChat Pay</th>
    <th>Alipay</th>
  </tr>
  <tr>
    <td align="center"><img src="./docs/images/nimclip-wechat-pay.png" width="260" alt="WeChat Pay QR code for 胡图图不涂涂"></td>
    <td align="center"><img src="./docs/images/nimclip-alipay.png" width="260" alt="Alipay QR code for 胡图图不涂涂"></td>
  </tr>
  <tr>
    <td align="center" colspan="2">Recipient: 胡图图不涂涂</td>
  </tr>
</table>

## Installation

Download the appropriate archive from [GitHub Releases](https://github.com/hukdoesn/Nimclip/releases):

- Apple Silicon: `Nimclip-macOS-arm64.zip`
- Intel: `Nimclip-macOS-x86_64.zip`

1. Unzip the archive and move `Nimclip.app` into the Applications folder.
2. Open Nimclip.
3. Press <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> to open clipboard history.

Nimclip requires macOS 15.0 or later. Direct paste requires macOS Accessibility permission. Without it, Nimclip can still copy the selected item so you can paste it manually.

### First launch

If macOS prevents Nimclip from opening:

1. Double-click `Nimclip.app` once, then close the system warning.
2. Open System Settings → Privacy & Security.
3. Find Nimclip in the Security section and click **Open Anyway**.
4. Enter your Mac login password and confirm.

If it is still blocked, verify that the archive came from the Nimclip repository, then run:

```bash
xattr -dr com.apple.quarantine "/Applications/Nimclip.app"
open "/Applications/Nimclip.app"
```

## License

Nimclip is open source under the [Apache License 2.0](./LICENSE). Modified or redistributed versions must retain `LICENSE`, `NOTICE`, the original project attribution, and a notice describing the changes.

Project home: <https://github.com/hukdoesn/Nimclip>

<div align="center">
  <sub>© 2026 hukdoesn ｜ 胡图图不涂涂</sub>
</div>
