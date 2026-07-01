# SkipFace 隐私政策 / Privacy Policy

> 生效日期 / Effective date：2026-07-01
> 版本 / Version：v1.0

> 说明：本文档中标注【】的项为占位符，发布前请开发者替换为真实信息（开发者名称、联系邮箱等）。

---

## 简体中文

### 引言

SkipFace（以下简称"本应用"）是一款隐私优先、纯本地运行的照片人脸遮挡工具。开发者【请填写：开发者/公司名称】非常重视你的个人信息与隐私保护。本隐私政策用于说明本应用如何处理与保护你的信息。**请在使用本应用前仔细阅读本政策。**

一句话概括：**本应用不收集、不存储、不上传你的任何个人信息，全部处理均在你的设备本地完成，且不申请任何敏感权限的静态授权。**

### 一、我们收集的个人信息

**本应用不收集任何个人信息**，也不会将你的照片、人脸数据或使用记录上传至任何服务器或第三方。具体而言：

- **照片内容**：你选择或拍摄的照片仅在本机内存/本地缓存中用于遮挡处理，不会被上传或共享给开发者及任何第三方。
- **人脸识别数据**：人脸检测由 HarmonyOS 系统能力（Core Vision Kit）在设备本地完成，检测结果仅用于在当前编辑会话中定位遮挡，处理后不持久保存、不外传。
- **账号信息**：本应用无需注册、无需登录，不收集任何账号或身份信息。
- **设备与日志信息**：本应用不收集设备标识符，不接入任何统计、广告或崩溃上报的第三方 SDK。

### 二、权限调用说明

本应用**未在应用包中静态声明任何敏感权限**。以下能力均通过系统提供的选择器或安全控件按需触发，授权范围最小、且由系统管理：

| 能力 | 实现方式 | 用途 | 是否需要静态权限 |
| --- | --- | --- | --- |
| 选择照片 | 系统图片选择器（PhotoViewPicker） | 让你从相册选择待处理的照片 | 否 |
| 拍摄照片 | 系统安全相机控件（CameraPicker） | 让你现场拍摄待处理的照片 | 否 |
| 保存到相册 | 安全控件 SaveButton（一次性授权） | 将处理后的图片保存到你的相册 | 否 |
| 分享 | 系统分享面板 | 将处理后的图片分享给你选择的应用 | 否 |

上述操作均由你主动发起，系统在需要时弹出授权，本应用不会在后台静默访问你的相册、相机或文件。

### 三、信息的存储与保护

- **本地设置**：你的偏好设置（如默认遮挡模式、Emoji 列表、主题、自定义字体路径等）仅保存在设备本地（系统 Preferences）。
- **临时文件**：使用"分享"功能时，处理后的图片会写入应用的本地缓存目录以供系统分享，属于临时文件，你可在系统中清理应用缓存将其删除。
- **自定义字体**：你导入的字体文件会复制到应用私有沙箱目录，仅用于遮挡文字渲染，可在设置中删除。
- 以上数据均不离开你的设备。卸载本应用即会清除应用私有数据。

### 四、信息的对外提供、共享、转让与公开披露

本应用**不向任何第三方提供、共享、转让或公开披露**你的个人信息，因为本应用不收集此类信息。你主动使用"分享"功能时，图片的去向完全由你在系统分享面板中的选择决定，与开发者无关。

### 五、第三方 SDK

本应用**未集成任何第三方数据收集类 SDK**（包括但不限于统计分析、广告、推送、社交 SDK）。人脸检测等能力使用 HarmonyOS 系统自带的服务（Core Vision Kit），在设备本地运行，不涉及第三方数据传输。

### 六、未成年人保护

本应用面向一般用户，不专门面向未成年人，且不收集任何个人信息。若你是未成年人，建议在监护人指导下使用。若监护人对未成年人使用本应用有疑问，可通过下方方式联系我们。

### 七、你的权利

由于本应用不收集你的个人信息，不涉及个人信息的查询、更正、删除或账号注销。对于本地存储的设置与文件，你可随时：

- 在应用"设置"中修改或删除偏好、Emoji、字体；
- 在系统中清理应用缓存；
- 卸载应用以清除全部本地数据。

### 八、本政策的更新

我们可能适时更新本隐私政策。更新后将在本页更新"生效日期"并通过应用版本发布说明或应用内提示告知。请定期查阅。

### 九、联系我们

如对本隐私政策或你的隐私有任何疑问、意见或投诉，请通过以下方式联系：

- 开发者：【请填写：开发者/公司名称】
- 邮箱：【请填写：联系邮箱，例如 privacy@example.com】
- 源码与反馈：https://github.com/LZZLHY/skipface

---

## English

### Introduction

SkipFace ("the App") is a privacy-first, fully on-device photo face-hiding tool. The developer 【Developer/Company name】 takes your personal information and privacy seriously. This Privacy Policy explains how the App handles and protects your information. **Please read it carefully before using the App.**

In one sentence: **the App does not collect, store, or upload any of your personal information; all processing happens locally on your device, and it declares no static sensitive permissions.**

### 1. Personal Information We Collect

**The App collects no personal information**, and never uploads your photos, face data, or usage records to any server or third party. Specifically:

- **Photo content**: photos you select or capture are used only in local memory/cache for masking, and are never uploaded or shared with the developer or any third party.
- **Face detection data**: face detection is performed on-device by the HarmonyOS system capability (Core Vision Kit). Results are used only to position masks within the current editing session, and are not persisted or transmitted.
- **Account information**: no registration or sign-in is required; no account or identity information is collected.
- **Device & log information**: no device identifiers are collected; no third-party analytics, advertising, or crash-reporting SDKs are integrated.

### 2. Permissions

The App **declares no static sensitive permissions**. The following capabilities are triggered on demand via system pickers or secure controls, with minimal, system-managed scope:

| Capability | Mechanism | Purpose | Static permission required |
| --- | --- | --- | --- |
| Pick photo | System image picker (PhotoViewPicker) | Choose a photo from your album | No |
| Take photo | System secure camera control (CameraPicker) | Capture a photo to process | No |
| Save to album | Secure SaveButton (one-time grant) | Save the processed image to your album | No |
| Share | System share sheet | Share the processed image to an app you choose | No |

All actions are initiated by you; the App does not silently access your album, camera, or files in the background.

### 3. Storage & Protection

- **Local settings**: preferences (default mask mode, emoji list, theme, custom font paths, etc.) are stored only on-device (system Preferences).
- **Temporary files**: when you use Share, the processed image is written to the App's local cache for the system share flow; it is a temporary file and can be removed by clearing the App cache.
- **Custom fonts**: fonts you import are copied into the App's private sandbox, used only for mask text rendering, and can be deleted in Settings.
- None of this data leaves your device. Uninstalling the App removes its private data.

### 4. Sharing, Transfer & Disclosure

The App **does not provide, share, transfer, or publicly disclose** your personal information to any third party, because it collects none. When you use Share, the destination is entirely determined by your choice in the system share sheet, independent of the developer.

### 5. Third-Party SDKs

The App **integrates no third-party data-collection SDKs** (including analytics, advertising, push, or social SDKs). Capabilities such as face detection use built-in HarmonyOS system services (Core Vision Kit) running on-device, with no third-party data transfer.

### 6. Children's Privacy

The App targets general users, is not directed at children, and collects no personal information. Minors should use it under guardian guidance. Guardians with questions may contact us below.

### 7. Your Rights

Since the App collects no personal information, there is no personal data to access, correct, delete, or de-register. For locally stored settings and files, you may at any time: edit or remove preferences/emoji/fonts in Settings, clear the App cache in the system, or uninstall the App to erase all local data.

### 8. Updates to This Policy

We may update this Privacy Policy from time to time. Updates will be reflected in the "Effective date" on this page and announced via release notes or in-app notice. Please review periodically.

### 9. Contact Us

For any questions, comments, or complaints about this Privacy Policy or your privacy:

- Developer: 【Developer/Company name】
- Email: 【Contact email, e.g. privacy@example.com】
- Source & feedback: https://github.com/LZZLHY/skipface
