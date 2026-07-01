<div align="center">

<img src="docs/assets/logo-rounded.png" width="120" alt="SkipFace" />

# SkipFace

**On-device face-hiding tool for HarmonyOS**

Auto face detection · Emoji cover · Gaussian / pixelate / halftone blur · Free editing · Fully offline

<p>
<img alt="HarmonyOS" src="https://img.shields.io/badge/HarmonyOS-6.1.0%20(API%2023)-0A59F7" />
<img alt="Language" src="https://img.shields.io/badge/Language-ArkTS-3AC569" />
<img alt="License" src="https://img.shields.io/badge/License-MIT-blue" />
<img alt="stars" src="https://img.shields.io/github/stars/LZZLHY/skipface?style=flat" />
</p>

[简体中文](README.md) · **English**

</div>

---

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
- Privacy Policy: <https://lzzlhy.github.io/skipface/privacy-en.html>

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

### 🧩 Face Detection

Detection uses the system Core Vision Kit (`@kit.CoreVisionKit`) and **bundles no third-party model weights**. The detector is decoupled behind the `FaceDetector` interface; to use a custom model, implement the interface and swap one line in `AppContainer.init()`.

### 📜 License

Released under the [MIT](LICENSE) license. Face detection relies on system capabilities; no attribution-required third-party model or runtime is bundled.
