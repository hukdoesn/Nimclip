<div align="center">
  <img src="./Cliplet/Assets.xcassets/NimclipAppIcon.imageset/nimclip-app-icon.png" width="112" height="112" alt="Nimclip 图标">
  <h1>Nimclip</h1>
  <p>macOS 剪贴板历史工具</p>
  <p><strong>简体中文</strong> · <a href="./README_EN.md">English</a></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-15.0%2B-242424?style=flat-square&logo=apple&logoColor=white" alt="macOS 15.0+">
    <img src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-supported-554f49?style=flat-square" alt="Apple Silicon and Intel">
    <img src="https://img.shields.io/badge/License-Apache--2.0-71685f?style=flat-square" alt="Apache License 2.0">
    <img src="https://img.shields.io/github/downloads/hukdoesn/Nimclip/total?style=flat-square&label=Release%20Downloads&color=5f6f65" alt="GitHub Releases 总下载量">
  </p>
</div>

<p align="center">
  <img src="./docs/images/nimclip-macbook-themes.png" width="1120" alt="Nimclip 浅色和深色界面">
</p>

## Nimclip 是什么

Nimclip 是一款免费、开源、本地优先的原生 macOS 剪贴板历史工具，使用 Swift、SwiftUI 与 SwiftData 开发并常驻菜单栏。按下 <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd>，即可查找、整理和粘贴之前复制过的内容。

## 功能

macOS 系统剪贴板只保留当前一次复制的内容，再次复制后上一条就会被覆盖。Nimclip 提供：

- 记录文字、链接、代码、图片和富文本，并保留来源应用名称与图标
- 自动识别链接与常见代码内容，支持按全部、文本、链接、代码和图片筛选
- 搜索正文、图片识别文字、来源应用名称和标签
- 收藏重要记录，创建、重命名、删除彩色标签并按标签筛选
- 保留富文本原始格式和图片内容，也可选择复制或粘贴为纯文本
- 按选择顺序合并多条文本，一次复制或粘贴
- 图片缩略图、完整图片预览和可滚动的长文本预览
- 重复复制同一内容时更新其时间并移到最新位置，不重复保存相同记录
- 自定义全局快捷键、历史上限、保留时间和登录时启动
- 暂停或恢复剪贴板记录
- 独立的浅色、深色外观，以及简体中文、英文即时切换
- 启动后和运行期间自动检查 GitHub Releases 新版本

## 快速使用

| 操作 | 使用方式 |
| --- | --- |
| 打开历史 | 点击菜单栏图标，或按默认快捷键 <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> |
| 搜索 | 打开后直接输入；搜索框会自动获得焦点 |
| 选择记录 | 使用 <kbd>↑</kbd>、<kbd>↓</kbd> 在结果间移动 |
| 粘贴 | 单击记录，或选中后按 <kbd>Return</kbd> |
| 预览 | 将鼠标移到记录上并按住 <kbd>⌥ Option</kbd> |
| 更多操作 | 右键记录，可复制、纯文本复制/粘贴、收藏、添加标签、打开链接或删除 |
| 删除记录 | 选中后按 <kbd>Delete</kbd>，或使用右键菜单 |
| 多条拼贴 | 点击顶部的多条拼贴按钮，按所需顺序选择文本，再复制或粘贴 |
| 关闭面板 | 按 <kbd>Esc</kbd>，或点击面板外部 |

每次重新打开面板时，Nimclip 都会选中当前搜索和筛选结果中的第一条记录，并将列表滚动到顶部，方便立即使用最新内容。

## 界面

### 图片预览

图片会在历史记录中显示缩略图，并可以打开完整预览。长文本同样支持独立预览和滚动查看。

<p align="center">
  <img src="./docs/images/nimclip-image-preview-real.png" width="780" alt="Nimclip 图片预览">
</p>

### 图片文字识别

图片文字识别默认开启。开启后新复制的图片会自动使用 macOS Vision OCR 建立本地文字索引，因此可以直接使用图片中的文字搜索对应图片。自动识别不追溯处理升级前已经保存的历史图片，避免软件升级后突然长时间占用 CPU；这部分只需手动补建一次，完成后无需重复操作。

- 支持自动检测语言，重点识别简体中文和英文
- 可在“设置 → 图片文字识别”中关闭自动识别
- 可以在“补建历史图片索引”中为旧图片批量建立一次索引，并查看进度或随时停止
- OCR 只用于建立搜索索引，不会改变保存的原始图片
- 识别任务在本机低优先级串行执行，不上传图片，完成后不会持续占用 CPU

### 设置

可以设置应用语言、界面外观、全局快捷键、历史上限、保留时间、图片文字识别、登录时启动和直接粘贴权限。

<p align="center">
  <img src="./docs/images/nimclip-settings-themes.png" width="1120" alt="Nimclip 设置页面">
</p>

默认设置：

| 设置 | 默认值 | 可调整范围 |
| --- | --- | --- |
| 全局快捷键 | <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> | 可在应用内重新录制 |
| 历史数量 | 500 条 | 100–5000 条 |
| 保留时间 | 7 天 | 1–365 天 |
| 图片文字识别 | 开启 | 可关闭，也可手动补建已有图片索引 |
| 登录时启动 | 关闭 | 可在设置中开启 |

### 关于

关于页包含版本、开源许可、项目主页、联系作者和赞赏支持入口。“项目主页”会使用 macOS 默认浏览器打开 GitHub；“赞赏支持”会显示微信支付与支付宝收款码。

<p align="center">
  <img src="./docs/images/nimclip-about-themes.png" width="1120" alt="Nimclip 关于页面">
</p>

### 更新提醒

Nimclip 启动约 4 秒后会检查一次 GitHub Releases，之后在运行期间每 10 分钟检查一次。只会提示比当前版本新的正式版本，自动检查失败时不会打扰使用；也可以从“关于”页手动检查。

发现新版本时可以直接前往 Release 页面下载。同一版本的自动提醒至少间隔 24 小时，升级应用不会清除保存在这台 Mac 上的历史记录。

<p align="center">
  <img src="./docs/images/nimclip-update-notification.png" width="1120" alt="Nimclip 新版本更新提醒">
</p>

## 数据与隐私

Nimclip 使用 SwiftData 在本机持久化历史记录，底层为 SQLite。退出应用或重启 Mac 后，记录不会丢失。

- 所有剪贴板内容只保存在当前 Mac
- 不需要账户，不会上传剪贴板内容
- 图片文字识别完全使用 macOS 系统 Vision OCR；用于识别的工作图最大边会缩放至 2560 像素，但不会修改原图
- 默认保留 `500` 条、`7` 天，收藏内容不会被自动清理
- 执行“清空历史”时会保留收藏记录；单独删除记录时会同时清理对应的本地图片文件
- 历史和设置：`~/Library/Application Support/Cliplet.store`
- 图片：`~/Library/Application Support/Cliplet/ClipboardImages/`

Nimclip 的自动更新检查只会请求 GitHub 的公开 Release 信息，不会附带或上传剪贴板内容。

## 赞赏支持

Nimclip 是免费开源项目，所有功能都可以免费使用。如果它对你有帮助，也可以自愿请作者喝杯咖啡。

<table align="center">
  <tr>
    <th>微信支付</th>
    <th>支付宝</th>
  </tr>
  <tr>
    <td align="center"><img src="./docs/images/nimclip-wechat-pay.png" width="260" alt="微信支付收款码"></td>
    <td align="center"><img src="./docs/images/nimclip-alipay.png" width="260" alt="支付宝收款码"></td>
  </tr>
</table>

## 安装

安装包：

- Apple Silicon（M1、M2、M3、M4 等）：`Nimclip-macOS-arm64.zip`
- Intel：`Nimclip-macOS-x86_64.zip`

1. 从 [GitHub Releases](https://github.com/hukdoesn/Nimclip/releases) 下载与 Mac 芯片对应的安装包。
2. 解压后将 `Nimclip.app` 移入“应用程序”文件夹。
3. 打开 Nimclip，使用 <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> 唤起剪贴板历史。

支持 macOS 15.0 及更高版本。“直接粘贴”需要 macOS 辅助功能权限；未授权时仍可以复制选中内容后手动粘贴。

Nimclip 同时提供 Apple Silicon 和 Intel 安装包。下载数量徽章统计 GitHub Releases 中所有安装包资源的累计下载次数。

### 首次打开

如果系统阻止打开 Nimclip：

1. 双击一次 `Nimclip.app`，然后关闭系统提示。
2. 打开“系统设置”→“隐私与安全性”。
3. 在“安全性”区域找到 Nimclip，点击“仍要打开”（Open Anyway）。
4. 输入 Mac 登录密码，再次确认打开。

**如果仍提示无法打开**

确认安装包来自 Nimclip 项目主页后，打开“终端”执行：

```bash
xattr -dr com.apple.quarantine "/Applications/Nimclip.app"
open "/Applications/Nimclip.app"
```

### 直接粘贴权限

Nimclip 会先把选中的历史内容写回系统剪贴板，再模拟粘贴到之前正在使用的应用。若要启用直接粘贴：

1. 打开 Nimclip“设置 → 直接粘贴”。
2. 点击“系统设置”。
3. 在“隐私与安全性 → 辅助功能”中允许 Nimclip。

不授予辅助功能权限不会影响历史记录、搜索、复制、OCR 或预览；按下粘贴时，Nimclip 会改为仅复制，随后可手动按 <kbd>⌘</kbd> <kbd>V</kbd>。

## 从源码构建

要求：

- macOS 15.0 或更高版本
- Xcode 16 或更高版本
- Swift 6

克隆项目后，可以使用 Xcode 打开 `Cliplet.xcodeproj`，也可以在项目根目录执行：

```bash
xcodebuild build \
  -project Cliplet.xcodeproj \
  -scheme Cliplet \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project Cliplet.xcodeproj \
  -scheme Cliplet \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

生成可分发的 ad-hoc 签名 ZIP：

```bash
./package.sh arm64
./package.sh x86_64
```

产物会生成到 `dist/`，同时包含对应 ZIP 的 SHA-256 校验文件。未使用 Apple Developer ID 签名和公证的自构建版本，首次打开时可能仍需要按照上面的步骤处理 Gatekeeper 提示。

## 社区

- [LINUX DO — 新的理想型社区](https://linux.do/)

## 开源许可

Nimclip 基于 [Apache License 2.0](./LICENSE) 开源。修改或重新分发时，请保留 `LICENSE`、`NOTICE` 和 Nimclip 原项目归属说明，并标明已修改的内容。

项目主页：<https://github.com/hukdoesn/Nimclip>

<div align="center">
  <sub>© 2026 hukdoesn ｜ 胡图图不涂涂</sub>
</div>
