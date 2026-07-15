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
    height: auto;
    margin: 0;
  }

  .nimclip-shot a {
    display: block;
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

  .nimclip-gallery--menu {
    grid-template-columns: repeat(2, minmax(0, 440px));
    justify-content: center;
  }

  .nimclip-resolution-note {
    margin: -0.75rem 0 2rem;
    color: #6e7781;
    font-size: 0.85rem;
    text-align: center;
  }

  .nimclip-shot--compact {
    max-width: 887px;
    margin-right: auto;
    margin-left: auto;
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

<div class="nimclip-gallery nimclip-gallery--menu">
  <figure class="nimclip-shot">
    <a href="./images/nimclip-menu-light@2x.png" aria-label="查看浅色主界面原图 / View the full-size light-mode window">
      <img src="./images/nimclip-menu-light@2x.png" width="880" height="1200" alt="Nimclip clipboard history in light mode" decoding="async" fetchpriority="high">
    </a>
    <figcaption>浅色主题 / Light theme</figcaption>
  </figure>
  <figure class="nimclip-shot">
    <a href="./images/nimclip-menu-dark@2x.png" aria-label="查看深色主界面原图 / View the full-size dark-mode window">
      <img src="./images/nimclip-menu-dark@2x.png" width="880" height="1200" alt="Nimclip clipboard history in dark mode" decoding="async">
    </a>
    <figcaption>深色主题 / Dark theme</figcaption>
  </figure>
</div>
<p class="nimclip-resolution-note">点击图片查看 @2x 原图 / Click an image to view the full @2x capture</p>

## 功能 / Features

- 文字、链接、代码、图片和富文本历史
- 搜索、类型筛选、收藏和标签
- 来源应用名称与图标
- 纯文本粘贴和多条内容合并
- 自定义保留数量、保留时间、快捷键和外观
- 所有剪贴板数据只保存在当前 Mac，不需要账号，不上传云端

---

- History for text, links, code, images, and rich text
- Search, filters, favorites, tags, and source application details
- Plain-text paste and multi-item merging
- Configurable retention, global shortcut, and appearance
- All clipboard data stays on your Mac—no account and no cloud upload

## 界面预览 / Interface Preview

### 图片历史 / Image History

复制图片后可直接在历史记录中查看缩略图和大图预览。

Copied images remain easy to identify with thumbnails and a full-size preview.

<div class="nimclip-gallery">
  <figure class="nimclip-shot">
    <a href="./images/nimclip-image-preview-light@2x.png" aria-label="查看浅色图片预览原图 / View the full-size light image preview">
      <img src="./images/nimclip-image-preview-light@2x.png" width="1008" height="726" alt="Nimclip image clipboard preview in light mode" loading="lazy" decoding="async">
    </a>
    <figcaption>浅色图片预览 / Light image preview</figcaption>
  </figure>
  <figure class="nimclip-shot">
    <a href="./images/nimclip-image-preview-dark@2x.png" aria-label="查看深色图片预览原图 / View the full-size dark image preview">
      <img src="./images/nimclip-image-preview-dark@2x.png" width="1008" height="726" alt="Nimclip image clipboard preview in dark mode" loading="lazy" decoding="async">
    </a>
    <figcaption>深色图片预览 / Dark image preview</figcaption>
  </figure>
</div>

### 个性化设置 / Personalization

快捷键、保留规则、粘贴行为和外观均可按自己的工作流调整。

Customize shortcuts, retention, paste behavior, and appearance for your workflow.

<div class="nimclip-gallery">
  <figure class="nimclip-shot">
    <a href="./images/nimclip-settings-light@2x.png" aria-label="查看浅色设置页面原图 / View the full-size light settings window">
      <img src="./images/nimclip-settings-light@2x.png" width="1320" height="1040" alt="Nimclip settings in light mode" loading="lazy" decoding="async">
    </a>
    <figcaption>浅色设置 / Light settings</figcaption>
  </figure>
  <figure class="nimclip-shot">
    <a href="./images/nimclip-settings-dark@2x.png" aria-label="查看深色设置页面原图 / View the full-size dark settings window">
      <img src="./images/nimclip-settings-dark@2x.png" width="1320" height="1040" alt="Nimclip settings in dark mode" loading="lazy" decoding="async">
    </a>
    <figcaption>深色设置 / Dark settings</figcaption>
  </figure>
</div>

### 原生体验 / Native Experience

<div class="nimclip-gallery">
  <figure class="nimclip-shot">
    <a href="./images/nimclip-about-light@2x.png" aria-label="查看浅色关于页面原图 / View the full-size light About window">
      <img src="./images/nimclip-about-light@2x.png" width="1040" height="886" alt="Nimclip About window in light mode" loading="lazy" decoding="async">
    </a>
    <figcaption>浅色关于页面 / Light About window</figcaption>
  </figure>
  <figure class="nimclip-shot">
    <a href="./images/nimclip-about-dark@2x.png" aria-label="查看深色关于页面原图 / View the full-size dark About window">
      <img src="./images/nimclip-about-dark@2x.png" width="1040" height="886" alt="Nimclip About window in dark mode" loading="lazy" decoding="async">
    </a>
    <figcaption>深色关于页面 / Dark About window</figcaption>
  </figure>
</div>

<figure class="nimclip-shot nimclip-shot--compact">
  <a href="./images/nimclip-update-notification.png" aria-label="查看更新提醒原图 / View the full-size update notification">
    <img src="./images/nimclip-update-notification.png" width="1774" height="1348" alt="Nimclip update notification" loading="lazy" decoding="async">
  </a>
  <figcaption>内置更新提醒 / Built-in update notification</figcaption>
</figure>

## 安装 / Installation

Nimclip 支持 macOS 15.0 及以上系统。GitHub Releases 提供 Apple Silicon 和 Intel 安装包。

Nimclip requires macOS 15.0 or later. GitHub Releases include builds for Apple Silicon and Intel Macs.

- [Apple Silicon (`arm64`)](https://github.com/hukdoesn/Nimclip/releases/latest)
- [Intel (`x86_64`)](https://github.com/hukdoesn/Nimclip/releases/latest)

项目采用 [Apache License 2.0](https://github.com/hukdoesn/Nimclip/blob/main/LICENSE) 开源。
