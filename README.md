<div align="center">

<img src="docs/assets/logo-rounded.png" width="120" alt="SkipFace" />

# SkipFace · 隐匿

**HarmonyOS 本地人脸隐匿工具**

一键识别照片人脸 · 表情遮挡 · 高斯 / 像素 / 半色调模糊 · 自由编辑 · 纯本地离线

<p>
<img alt="HarmonyOS" src="https://img.shields.io/badge/HarmonyOS-6.1.0%20(API%2023)-0A59F7" />
<img alt="Language" src="https://img.shields.io/badge/Language-ArkTS-3AC569" />
<img alt="License" src="https://img.shields.io/badge/License-MIT-blue" />
<img alt="stars" src="https://img.shields.io/github/stars/LZZLHY/skipface?style=flat" />
</p>

**简体中文** · [English](README_EN.md)

</div>

---

### 简介

**SkipFace（隐匿）** 是一款隐私优先、**纯本地运行**的 HarmonyOS 照片人脸遮挡工具。导入照片后自动识别人脸，并以表情覆盖或模糊 / 像素 / 半色调等方式遮挡，支持逐个手动增删改，原分辨率导出保存或分享。全程在本机完成，**不联网、不上传、不收集任何数据**。

### ✨ 功能特性

- **自动人脸检测**：基于 HarmonyOS 系统 Core Vision Kit，免模型文件、本地离线；遮挡跟随头部倾斜旋转。
- **两类遮挡**
  - 表情覆盖：内置可自定义 Emoji 调色板，支持键盘输入 / 粘贴任意 Emoji，支持自定义字体（TTF/OTF）。
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
- 隐私政策：<https://lzzlhy.github.io/skipface/privacy.html>

### 📱 设备适配

| 形态 | 断点 | 布局 |
| --- | --- | --- |
| 手机竖屏 | sm (<600vp) | 顶栏 + 画布 + 底部操作坞 |
| 折叠 / 横屏 / 小平板 | md (600–840vp) | 画布 + 右侧属性检查器 |
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

### 🧩 人脸检测说明

检测使用系统 Core Vision Kit（`@kit.CoreVisionKit`），**不随包分发任何第三方模型权重**。检测器通过统一 `FaceDetector` 接口解耦，若需替换为自研模型，实现该接口并在 `AppContainer.init()` 中替换一行即可。

### 📜 许可

本项目以 [MIT](LICENSE) 许可开源。人脸检测使用系统能力，未引入需署名的第三方模型或推理库。
