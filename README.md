# Nimclip

Nimclip 是一款面向 macOS 15 及更高版本的轻量原生剪贴板历史工具。它常驻菜单栏，通过 `Command-Shift-V` 快速查看、搜索和重新粘贴历史内容。

[在 GitHub 上为 Nimclip 点 Star](https://github.com/hukdoesn/Nimclip) · [反馈问题](https://github.com/hukdoesn/Nimclip/issues)

Nimclip 会保留一次复制事务中的纯文本、HTML、RTF/RTFD、图片及应用自定义剪贴板表示，并在重新复制或粘贴时按原 item 顺序写回。完全相同的内容和格式会自动去重；文字相同但格式不同的记录不会被错误合并。对于超过轻量存储上限或无法完整读取的事务，Nimclip 会提示并跳过记录，避免保存一个看似正常但已经丢失格式的副本。

## 高频操作

- 使用顶部类型栏快速筛选文本、链接、代码和图片，也可以叠加收藏与标签筛选。
- 悬停文字记录后可直接“以纯文本粘贴”，右键菜单也提供纯文本复制与粘贴，不必再经过文本编辑器清除格式。
- 点击顶部“多条拼贴”，按需要的顺序选择多段文字，即可一次复制或粘贴合并后的内容。
- 按住 `Option` 并悬停记录可查看完整内容，链接记录可以直接打开。

## 开源许可

Nimclip 采用 [Apache License 2.0](LICENSE)，并提供项目归属说明 [NOTICE](NOTICE)。欢迎使用、研究和二次开发；重新分发原项目或衍生作品时，需要遵守许可证第 4 节，包括：

- 向接收者提供 Apache License 2.0；
- 在修改过的文件中明确标注修改；
- 保留适用的版权、商标与归属声明；
- 在随衍生作品分发的 `NOTICE`、源码、文档或通常展示第三方声明的界面中，保留 Nimclip 的原项目归属。

原项目地址：<https://github.com/hukdoesn/Nimclip>

## 数据与隐私

- 历史、标签和设置通过 SwiftData 持久化到本机 SQLite 数据库 `~/Library/Application Support/Cliplet.store`，并非仅保存在内存中；运行时还会有 SQLite 的 `-wal` 与 `-shm` 辅助文件。
- 图片文件单独保存在用户 `Application Support/Cliplet/ClipboardImages` 目录。
- Nimclip 不要求账户，也不会把剪贴板内容上传到远程服务。

## 本地运行

使用 Xcode 打开 `Cliplet.xcodeproj`，运行内部保留的 `Cliplet` scheme。应用安装和运行时显示为 Nimclip。完整测试命令：

```bash
xcodebuild test -project Cliplet.xcodeproj -scheme Cliplet -destination 'platform=macOS'
```

首次直接粘贴时，macOS 会请求辅助功能权限。未授予该权限时，Nimclip 仍会将选中内容复制回系统剪贴板。

## 打包

在项目根目录运行：

```bash
./package.sh
```

脚本会基于 `Application_logo` 中的品牌资源重新生成菜单栏图标和 AppIcon，构建 Apple Silicon Release 版本，添加本机 ad-hoc 签名，并在 `dist/` 输出：

- `Nimclip.app`
- `Nimclip-macOS-arm64.zip`

当前脚本生成 arm64 软件包，需要在 macOS 与完整 Xcode 环境中执行。
