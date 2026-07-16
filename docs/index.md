---
title: Nimclip
description: A native, local-first clipboard history manager for macOS.
image: https://hukdoesn.github.io/Nimclip/images/nimclip-macbook-themes.png
---

<style>
  .nimclip-hero {
    padding: 1.5rem 0 0.5rem;
    text-align: center;
  }

  .nimclip-hero img {
    border-radius: 24px;
  }

  .nimclip-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    justify-content: center;
    margin: 1.25rem 0;
  }

  .nimclip-actions a {
    border: 1px solid #d0d7de;
    border-radius: 999px;
    padding: 0.55rem 1rem;
    text-decoration: none;
  }

  .nimclip-actions a:first-child {
    background: #24292f;
    border-color: #24292f;
    color: #fff;
  }

  .nimclip-shot {
    margin: 1.5rem 0 2rem;
    overflow: hidden;
    border: 1px solid #d8dee4;
    border-radius: 18px;
    background: #f6f8fa;
    box-shadow: 0 16px 40px rgba(31, 35, 40, 0.08);
  }

  .nimclip-shot img {
    display: block;
    width: 100%;
    margin: 0;
  }

  .nimclip-shot figcaption {
    padding: 0.8rem 1rem;
    color: #57606a;
    font-size: 0.9rem;
    text-align: center;
  }

  .nimclip-gallery {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1.25rem;
    margin: 1.5rem 0 2rem;
  }

  .nimclip-gallery .nimclip-shot {
    margin: 0;
  }

  @media (max-width: 720px) {
    .nimclip-gallery {
      grid-template-columns: 1fr;
    }

    .nimclip-shot {
      border-radius: 12px;
    }
  }
</style>

<div class="nimclip-hero">
  <img src="https://raw.githubusercontent.com/hukdoesn/Nimclip/main/Cliplet/Assets.xcassets/NimclipAppIcon.imageset/nimclip-app-icon.png" width="112" height="112" alt="Nimclip icon">
  <h1>Nimclip</h1>
  <p>免费开源、原生、本地优先的 macOS 剪贴板历史工具</p>
  <p>A free and open-source, native, local-first clipboard history manager for macOS.</p>
  <div class="nimclip-actions">
    <a href="https://github.com/hukdoesn/Nimclip/releases/latest"><strong>下载最新版本 / Download</strong></a>
    <a href="https://github.com/hukdoesn/Nimclip">查看源代码 / GitHub</a>
  </div>
</div>

<figure class="nimclip-shot">
  <img src="./images/nimclip-macbook-themes.png" alt="Nimclip clipboard history in light and dark themes">
  <figcaption>浅色与深色主题 / Light and dark themes</figcaption>
</figure>

## 功能 / Features

- 文字、链接、代码、图片和富文本历史
- 搜索、类型筛选、收藏和标签；图片可通过识别出的文字搜索
- 来源应用名称与图标
- 纯文本粘贴和多条内容合并
- 自定义保留数量、保留时间、快捷键和外观
- 所有剪贴板数据只保存在当前 Mac，不需要账号，不上传云端
- 图片文字识别使用 macOS 系统 OCR，在本机低优先级串行执行

---

- History for text, links, code, images, and rich text
- Search, filters, favorites, tags, source application details, and images by recognized text
- Plain-text paste and multi-item merging
- Configurable retention, global shortcut, and appearance
- All clipboard data stays on your Mac—no account and no cloud upload
- Image text recognition uses macOS system OCR in a low-priority on-device serial queue

## 界面预览 / Interface Preview

### 图片历史 / Image History

复制图片后可直接在历史记录中查看缩略图和大图预览。

Copied images remain easy to identify with thumbnails and a full-size preview.

<figure class="nimclip-shot">
  <img src="./images/nimclip-image-preview-real.png" alt="Nimclip image clipboard preview" loading="lazy">
  <figcaption>图片缩略图与大图预览 / Image thumbnails and full preview</figcaption>
</figure>

### 个性化设置 / Personalization

快捷键、保留规则、图片文字识别、粘贴行为和外观均可按自己的工作流调整。

Customize shortcuts, retention, on-device image text recognition, paste behavior, and appearance for your workflow.

<figure class="nimclip-shot">
  <img src="./images/nimclip-settings-themes.png" alt="Nimclip settings in light and dark themes" loading="lazy">
  <figcaption>完整设置页面 / Complete settings</figcaption>
</figure>

### 原生体验 / Native Experience

Nimclip 启动后会检查更新，并在运行期间每 10 分钟自动检查一次；同一版本不会频繁提醒。

Nimclip checks after launch and every 10 minutes while running, without repeatedly reminding you about the same version.

<div class="nimclip-gallery">
  <figure class="nimclip-shot">
    <img src="./images/nimclip-about-themes.png" alt="Nimclip about window in light and dark themes" loading="lazy">
    <figcaption>原生关于页面 / Native About window</figcaption>
  </figure>
  <figure class="nimclip-shot">
    <img src="./images/nimclip-update-notification.png" alt="Nimclip update notification" loading="lazy">
    <figcaption>内置更新提醒 / Built-in update notification</figcaption>
  </figure>
</div>

## 安装 / Installation

Nimclip 支持 macOS 15.0 及以上系统。GitHub Releases 提供 Apple Silicon 和 Intel 安装包。

Nimclip requires macOS 15.0 or later. GitHub Releases include builds for Apple Silicon and Intel Macs.

- [Apple Silicon (`arm64`)](https://github.com/hukdoesn/Nimclip/releases/latest)
- [Intel (`x86_64`)](https://github.com/hukdoesn/Nimclip/releases/latest)

项目采用 [Apache License 2.0](https://github.com/hukdoesn/Nimclip/blob/main/LICENSE) 开源。
