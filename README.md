<div align="center">

<img src="docs/assets/logo.png" width="120" alt="SkipFace" />

# SkipFace · 隐匿

**HarmonyOS 本地人脸隐匿工具**

一键识别照片人脸 · 表情遮挡 · 高斯 / 像素 / 半色调模糊 · 自由编辑 · 纯本地离线

<p>
<img alt="HarmonyOS" src="https://img.shields.io/badge/HarmonyOS-6.1.0%20(API%2023)-0A59F7" />
<img alt="Language" src="https://img.shields.io/badge/Language-ArkTS-3AC569" />
<img alt="License" src="https://img.shields.io/badge/License-MIT-blue" />
<img alt="stars" src="https://img.shields.io/github/stars/LZZLHY/skipface?style=flat" />
</p>

**简体中文** · [English](#english)

</div>

---

## 简体中文

### 简介

**SkipFace（隐匿）** 是一款隐私优先、**纯本地运行**的 HarmonyOS 照片人脸遮挡工具。导入照片后自动识别人脸，并以表情覆盖或模糊/像素/半色调等方式遮挡，支持逐个手动增删改，原分辨率导出保存或分享。全程在本机完成，**不联网、不上传、不收集任何数据**。

### ✨ 功能特性

- **自动人脸检测**：基于 HarmonyOS 系统 Core Vision Kit，免模型文件、本地离线；遮挡跟随头部倾斜旋转。
- **两类遮挡**
  - 表情覆盖：内置可自定义 Emoji 调色板，支持键盘输入/粘贴任意 Emoji，支持自定义字体（TTF/OTF）。
  - 模糊遮挡：高斯模糊、像素化（马赛克）、半色调三种效果，可作用于「整张脸」或「仅眼部」，统一以旋转椭圆裁剪，观感自然。
- **自由编辑**：点选、拖动、缩放、旋转、长按删除；也可进入「添加模式」在任意位置新增遮挡。
- **高清导出**：编辑在轻量代理图上进行，导出时在**原始分辨率**重渲染，保证清晰度。
- **保存与分享**：通过系统 SaveButton 安全控件保存到相册（免静态权限）；或经系统分享面板分享。
- **一多适配**：手机（底部操作坞）、平板 / 2in1（右侧属性检查器）自适应布局。
- **主题**：跟随系统 / 浅色 / 深色三态，语义色板自动适配深浅。

### 🔒 隐私

- 图片与人脸识别全部在**设备本地**完成。
- **未声明任何敏感权限**：选图用系统图片选择器、拍照用系统安全相机控件、保存用 SaveButton 一次性授权——均无需静态权限。
- 不含任何网络请求与第三方数据采集 SDK。
- 详见 [隐私政策](docs/PRIVACY.md)。

### 📱 设备适配

| 形态 | 断点 | 布局 |
| --- | --- | --- |
| 手机竖屏 | sm (<600vp) | 顶栏 + 画布 + 底部操作坞 |
| 折叠/横屏/小平板 | md (600–840vp) | 画布 + 右侧属性检查器 |
| 平板横屏 / 2in1 | lg (≥840vp) | 更大画布 + 右侧常驻检查器 |

### 🧱 技术架构

单向数据流、清晰分层，状态管理统一使用 **状态管理 V2**（`@ObservedV2`/`@Trace`）：

```
UI 层 (Pages / Components / Views)
  → 状态层 (EditorViewModel / SettingsViewModel)
    → 领域层 (UseCases + 纯数据模型)
      → 能力层 (inference 检测 / imaging 渲染) + 数据层 (Preferences / 相册文件)
```

- 依赖装配：轻量手写 DI 容器 `AppContainer`（启动时装配单例）。
- 检测器抽象 `FaceDetector`，默认实现 `CoreVisionFaceDetector`；可一行切换为自研实现。
- 渲染：预览用 ArkUI `Canvas`，导出用离屏 `OffscreenCanvas`，两条路径复用同一套绘制逻辑。

### 🚀 构建与运行

1. 使用 **DevEco Studio**（HarmonyOS SDK **6.1.0 (API 23)**，targetSdk **26.0.0**）打开工程根目录。
2. 安装依赖：`ohpm install`。
3. 配置签名：`File > Project Structure > Signing Configs` 勾选自动生成签名（需登录华为开发者账号）；确保产品已绑定签名配置。
4. 连接真机，`Sync` → `Build > Clean Project` → `Run`。

> 应用包名：`com.dhao.skipface`。

### 🧩 人脸检测说明

检测使用系统 Core Vision Kit（`@kit.CoreVisionKit`），**不随包分发任何第三方模型权重**。检测器通过统一 `FaceDetector` 接口解耦，若需替换为自研模型，实现该接口并在 `AppContainer.init()` 中替换一行即可。详见 `skipface/src/main/resources/rawfile/README.md`。

### 📜 许可

本项目以 **MIT** 许可开源（请在仓库根添加对应 `LICENSE` 文件）。人脸检测使用系统能力，未引入需署名的第三方模型或推理库。


---

## English

### Overview

**SkipFace** is a privacy-first, **fully on-device** face-hiding tool for HarmonyOS. Import a photo, faces are detected automatically, then covered with emoji or blur / pixelate / halftone effects. Every mask can be added, edited, or removed by hand, and the result is re-rendered at the original resolution for saving or sharing. Everything runs locally — **no network, no upload, no data collection**.

### ✨ Features

- **Automatic face detection** powered by the system Core Vision Kit — no model file, fully offline; masks follow head tilt.
- **Two masking styles**
  - Emoji cover: customizable emoji palette, keyboard/paste input for any emoji, custom fonts (TTF/OTF).
  - Blur mask: Gaussian blur, pixelate (mosaic) and halftone, applied to the whole face or eyes only, clipped as a rotated ellipse for a natural look.
- **Free editing**: tap to select, drag, resize, rotate, long-press to delete; or enter add mode to place a mask anywhere.
- **High-resolution export**: editing happens on a lightweight proxy image; export re-renders at the original resolution.
- **Save & share**: save to the album via the system SaveButton (no static permission) or share via the system share sheet.
- **Adaptive layout**: phone (bottom dock), tablet / 2-in-1 (side inspector).
- **Theming**: follow system / light / dark, with semantic color tokens.

### 🔒 Privacy

- Images and face detection are processed **entirely on the device**.
- **No sensitive permissions declared**: image picking, camera capture and album saving all use system pickers / one-time authorized controls.
- No network requests and no third-party data-collection SDKs.
- See the [Privacy Policy](docs/PRIVACY.md).

### 📱 Device Adaptation

| Form factor | Breakpoint | Layout |
| --- | --- | --- |
| Phone portrait | sm (<600vp) | Top bar + canvas + bottom dock |
| Foldable / landscape / small tablet | md (600–840vp) | Canvas + side inspector |
| Tablet landscape / 2-in-1 | lg (≥840vp) | Larger canvas + persistent inspector |

### 🧱 Architecture

Unidirectional data flow with clear layering, using **State Management V2** (`@ObservedV2` / `@Trace`):

```
UI (Pages / Components / Views)
  → State (EditorViewModel / SettingsViewModel)
    → Domain (UseCases + pure models)
      → Capability (inference / imaging) + Data (Preferences / album files)
```

- A lightweight hand-written DI container `AppContainer` wires singletons at startup.
- `FaceDetector` abstraction with `CoreVisionFaceDetector` as the default — swappable in one line.
- Rendering: ArkUI `Canvas` for preview and `OffscreenCanvas` for export, sharing the same drawing logic.

### 🚀 Build & Run

1. Open the project root in **DevEco Studio** (HarmonyOS SDK **6.1.0 (API 23)**, targetSdk **26.0.0**).
2. Install dependencies: `ohpm install`.
3. Configure signing: `File > Project Structure > Signing Configs`, enable automatic signature (Huawei developer account required) and make sure the product is bound to the signing config.
4. Connect a device, `Sync` → `Build > Clean Project` → `Run`.

> Bundle name: `com.dhao.skipface`.

### 🧩 Face Detection

Detection uses the system Core Vision Kit (`@kit.CoreVisionKit`) and **bundles no third-party model weights**. The detector is decoupled behind the `FaceDetector` interface; to use a custom model, implement the interface and swap one line in `AppContainer.init()`.

### 📜 License

Released under the **MIT** license (please add a `LICENSE` file at the repo root). Face detection relies on system capabilities; no attribution-required third-party model or runtime is bundled.
