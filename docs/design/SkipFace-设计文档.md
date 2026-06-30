# SkipFace 设计与开发文档

> 版本：v1.0 · 面向 HarmonyOS NEXT（API 23 / SDK 6.1.0，targetSdk 26.0.0）
> 设备形态：phone / tablet / 2in1（一次开发、多端部署）

---

## 0. 阅读对象与文档目标

本文档是 **SkipFace** 这款"本地人脸隐匿"应用在 HarmonyOS 上的完整设计蓝图，覆盖：

- 产品定位与功能边界
- 代码规范（强约束）
- HarmonyOS「一多」工程结构与响应式适配
- 分层技术架构与目录结构
- AI 人脸检测管线（使用开源上游模型）
- 遮挡渲染引擎（Emoji / 模糊 / 像素化 / 半色调）
- 数据模型、状态管理、关键交互流程
- 可拓展性与里程碑

> 本应用为**全新、从零实现**的原创工程。文档描述的是 SkipFace 自身的架构与算法，不依赖、不复制任何第三方应用的源码或资源；所有代码均需独立手写。所采用的神经网络模型为公开可商用的开源上游模型（YOLOv8-face 系列），仅以"模型权重"形式引入。

---

## 1. 产品概述

SkipFace 是一款**隐私优先、纯本地运行**的照片人脸遮挡工具。用户导入照片后，应用自动识别其中的人脸，并以可选的方式遮挡：

1. **Emoji 覆盖**：用表情符号盖住人脸，可跟随头部角度旋转。
2. **模糊遮挡**：高斯模糊 / 像素化 / 半色调三种风格，可作用于"整张脸"或"仅眼部"。

核心特性：

- **完全离线**：图像与模型推理全部在设备本地完成，不上传任何数据。
- **可手动编辑**：增/删/改每一个遮挡对象，调整大小、角度、表情。
- **一次开发多端部署**：手机、平板、2in1 自适应布局。
- **导出与分享**：保存到相册或分享到其它应用，原分辨率渲染。

---

## 2. 代码规范（强约束）

> 以下为本项目所有源码必须遵守的硬性要求。

### 2.1 注释要求（详细）

- **每个文件头部**：用块注释说明文件职责、所属分层、对外暴露的主要类型。
- **每个公开类 / 接口 / 结构体**：说明用途、生命周期、线程/并发约束。
- **每个公开方法**：说明入参、返回值、副作用、异常/失败路径；算法类方法必须解释**数学原理或坐标系约定**。
- **关键算法块**：逐步注释（如 letterbox 预处理、NMS、椭圆裁剪、StackBlur 等），让没有读过模型论文的人也能看懂。
- **坐标系**：凡涉及坐标的代码，注释必须标明所处坐标系（模型输入空间 / 原图空间 / 显示空间）及换算关系。
- 注释使用简体中文，术语保留英文（如 NMS、letterbox、PixelMap）。

### 2.2 原创性

- 全部代码**从零手写**，不得粘贴任何外部应用源码，不得保留任何第三方应用的命名、包名、字符串、资源、注释或彩蛋。
- 仅"算法思想"和"开源模型权重"可被借鉴/使用；具体实现需以本项目的架构与命名独立完成。

### 2.3 工程与语言约定

- 语言：ArkTS（UI 与业务）+ C/C++（仅在需要高性能像素处理 / 原生推理桥接时）。
- 严格模式：开启 `useNormalizedOHMUrl`、`caseSensitiveCheck`（已在 build-profile 中启用）。
- 命名：类型 `PascalCase`，变量/函数 `camelCase`，常量 `UPPER_SNAKE_CASE`，文件名与主类型同名。
- 状态管理统一使用 **状态管理 V2**（`@ObservedV2` / `@Trace` / `@Local` / `@Param` / `AppStorageV2`），避免 V1/V2 混用。
- 资源全部走资源系统（`$r('app.*')`），禁止硬编码颜色、字号、字符串。
- 异步统一 `async/await` + `Promise`，错误以 `Result` 风格（`{ ok, value, error }`）或受检异常向上传递，UI 层统一兜底提示。

---

## 3. HarmonyOS「一多」架构（一次开发，多端部署）

「一多」的核心是**同一套代码 + 工程化分层 + 响应式布局**，在不同设备上自动适配。SkipFace 从三个层面落实：

### 3.1 工程模块拆分（可拓展、可复用）

采用 **entry（HAP）+ 功能 HSP/HAR + 公共 HAR** 的分包结构：

```
SkipFace/
├── AppScope/                       # 应用级配置与资源
├── entry/                          # 入口 HAP（壳：路由、Ability、启动）
├── features/                       # 业务特性（按领域拆分，便于独立演进）
│   ├── editor/                     # 编辑器特性（HSP，可动态加载）
│   └── settings/                   # 设置特性（HSP）
├── commons/                        # 公共能力（HAR，多模块复用、可独立测试）
│   ├── basic/                      #   基础：日志、Result、断点、主题
│   ├── ui/                         #   通用 UI 组件（按钮、滑块、分段器、空态…）
│   ├── inference/                  #   AI 推理能力（模型加载/检测，封装 MindSpore Lite）
│   └── imaging/                    #   图像处理（PixelMap 工具、遮挡渲染引擎）
└── products/ (可选)                 # 不同分发产物的差异化壳
```

> 说明：当前仓库是单 `skipface` entry 模块，第一阶段可在 entry 内用相同的目录分层落地（见 §5），第二阶段再物理拆分为 HSP/HAR。**先保证分层清晰，再做物理拆包**，避免过早拆分带来的成本。

### 3.2 响应式适配（断点系统）

- **断点（Breakpoint）**：以窗口宽度划分 `sm`（< 600vp，手机竖屏）、`md`（600–840vp，平板/折叠展开/手机横屏）、`lg`（≥ 840vp，平板横屏 / 2in1）。
- 实现一个 `BreakpointService`：通过 `mediaquery` 或窗口尺寸监听，向 `AppStorageV2` 写入当前断点；页面用 `@Param`/订阅消费。
- 布局能力：优先使用 **栅格 `GridRow`/`GridCol`**、`Flex`、`Tabs`(底部/侧边可切换)、`Navigation`(自动 stack/split 模式) 等系统自适应容器。
- **同一页面、不同形态**：
  - `sm`：单栏，底部操作坞（Dock）。
  - `md/lg`：双栏，左画布 + 右"属性检查器"侧栏（Inspector），导航栏移到顶部/侧边。
- 资源限定目录：`base/`、`dark/`（已存在）、必要时增加 `*-zh_CN`、分辨率限定等。

### 3.3 设备能力差异

- 通过 `deviceTypes: ["phone","tablet","2in1"]`（已配置）声明支持端。
- 涉及能力差异（如相机、文件选择）用 `canIUse` / 能力查询做降级，不假设设备一定具备某能力。

---

## 4. 分层技术架构

采用清晰的**单向数据流 + 分层**（UI → 状态 → 领域 → 数据/能力），各层只依赖其下层接口：

```
┌──────────────────────────────────────────────┐
│  UI 层 (ArkUI Components / Pages)             │  纯展示 + 事件上抛
├──────────────────────────────────────────────┤
│  状态层 (EditorViewModel @ObservedV2)         │  持有 UI 状态、编排用例
├──────────────────────────────────────────────┤
│  领域层 (UseCases / 纯函数算法)                │  检测、定位、渲染、保存…
├──────────────────────────────────────────────┤
│  能力层 (inference / imaging) + 数据层 (repo) │  模型推理、像素处理、持久化
└──────────────────────────────────────────────┘
```

- **UI 层**：`@Component`/`@ComponentV2`，不写业务逻辑，仅绑定状态、上抛事件。
- **状态层**：`EditorViewModel`（`@ObservedV2`），暴露可观察状态字段（`@Trace`），方法即"动作"，内部调用领域用例并 `update` 状态。
- **领域层**：一组**无状态用例**（如 `DetectFacesUseCase`、`PlaceEmojiUseCase`、`BuildBlurRegionsUseCase`、`RenderMaskUseCase`、`ExportImageUseCase`），输入输出明确、易单测。
- **能力层**：`InferenceEngine`（封装模型）、`MaskRenderer`（封装渲染策略）。
- **数据层**：`SettingsRepository`（Preferences）、`PhotoRepository`（相册/文件）。

> 依赖注入：用一个轻量的 `AppContainer`（手写 DI 容器/工厂）在应用启动时装配单例（推理引擎、仓库），避免散落的全局单例，便于测试替换。

---

## 5. 目录结构（落地版）

第一阶段在 entry 模块内的建议结构（注释说明每个目录职责）：

```
skipface/src/main/
├── ets/
│   ├── entryability/                # UIAbility：处理冷启动 / 分享进入(want)
│   ├── pages/                       # 路由页面
│   │   ├── HomePage.ets             #   首页（空态 / 入口）
│   │   ├── EditorPage.ets           #   编辑器（核心，自适应单/双栏）
│   │   └── SettingsPage.ets         #   设置（全屏分组页）
│   ├── view/                        # 页面级可组合视图（按特性聚合）
│   │   ├── editor/                  #   画布、操作坞、属性检查器、遮挡叠加层
│   │   └── settings/                #   分组卡片、Emoji 编辑、字体管理
│   ├── components/                  # 通用 UI 组件（跨页面复用）
│   ├── viewmodel/                   # EditorViewModel / SettingsViewModel (@ObservedV2)
│   ├── domain/
│   │   ├── model/                   #   FaceDetection / Mask / EditorState …(纯数据)
│   │   └── usecase/                 #   各用例（纯逻辑）
│   ├── capability/
│   │   ├── inference/               #   InferenceEngine + 预/后处理（letterbox/NMS）
│   │   └── imaging/                 #   MaskRenderer + 模糊/像素/半色调算法
│   ├── data/
│   │   ├── settings/                #   SettingsRepository (Preferences)
│   │   └── photo/                   #   PhotoRepository (PhotoPicker / 相册保存 / 分享)
│   └── common/                      # 断点、主题、日志、Result、常量
├── cpp/                             # （可选）高性能像素核 / 原生推理桥
└── resources/
    ├── base/{element,media,profile} # 颜色/字号/字符串/媒体/页面配置
    ├── dark/element                 # 深色主题覆盖
    └── rawfile/                     # 模型文件 skipface_face.ms、内置 Emoji 字体等
```

---

## 6. AI 人脸检测管线

### 6.1 模型选型

- 采用开源上游 **YOLOv8-face**（5 关键点：左眼、右眼、鼻尖、左嘴角、右嘴角）。
- 推理框架：**HarmonyOS 系统自带 MindSpore Lite Kit**（`@kit.MindSporeLiteKit`）。
  - 离线把 `yolov8n-face.onnx` 转换为 MindSpore Lite 的 `.ms` 模型，置于 `resources/rawfile/skipface_face.ms`。
  - 优点：系统级、无需打包第三方 native 库、对端侧 NPU/CPU 有调度优化。
- 备选：若需自定义算子，可在 `cpp/` 内通过 NAPI 桥接其它推理后端；但**首选 MindSpore Lite**。

### 6.2 输入预处理（letterbox，640×640）

> 模型输入固定 `[1, 3, 640, 640]`，需保持长宽比缩放并居中填充。

步骤（注释要点写进代码）：

1. 取原图宽高 `w,h`，计算 `scale = min(640/w, 640/h)`。
2. 缩放后尺寸 `nw=w*scale, nh=h*scale`；居中偏移 `padX=(640-nw)/2, padY=(640-nh)/2`。
3. 画到 640×640 画布，空白区域填中性灰（`#808080`）。
4. 像素归一化到 `[0,1]`，按 **CHW**（先 R 平面，再 G，再 B）排布为 `Float32Array`。
5. 记录 `(scale, padX, padY)` 供后处理把坐标还原回原图。

### 6.3 推理

- 启动时**异步加载** + 一次 **warmup**（用全零张量跑一次，消除首帧抖动）。
- 单线程或按设备能力配置线程数；模型常驻单例（`InferenceEngine`）。

### 6.4 输出后处理（解码 + NMS）

- 模型输出张量形如 `[1, C, 8400]`（通道优先，`C = 总元素 / 8400`）。
  - 通道含义：`[0]=cx, [1]=cy, [2]=w, [3]=h, [4]=score`，其后为 5 个关键点（每点 `x,y(,conf)`）。
- 解码：
  1. 遍历 8400 个 anchor，`score ≥ 0.45` 保留。
  2. 框由中心宽高转左上角宽高，并 `(coord - pad)/scale` 还原到原图空间。
  3. 关键点同样 `(coord - pad)/scale` 还原。
- **NMS**：按 score 降序，IoU 阈值 `0.5` 抑制重叠框，得到最终人脸列表。

### 6.5 坐标 / 分辨率策略

- **检测在低分辨率代理图上进行**（长边压到 ~1024 的"显示图"），降低耗时、统一坐标系；所有编辑坐标都在该显示空间。
- **导出在原始全分辨率图上重渲染**：把遮挡对象坐标/尺寸按 `原图宽 / 显示图宽` 等比放大后再绘制，保证清晰度。
- 该"代理检测 + 高清导出"是性能与画质的关键平衡点，必须实现。

---

## 7. 遮挡渲染引擎

渲染采用**策略模式**：`MaskRenderer` 持有可插拔的 `MaskStrategy`（`EmojiStrategy` / `BlurStrategy`），便于未来扩展新效果。两套渲染路径：

- **预览渲染**：在 ArkUI `Canvas` 上实时绘制（叠加层），跟随手势/滑块即时反馈。
- **导出渲染**：在离屏 `PixelMap` 上以原图分辨率绘制，输出 PNG。

### 7.1 Emoji 渲染

- 圆心 = 人脸框中心。
- 直径采用**混合算法**避免方框拉伸：
  - `diffRatio = |w-h| / max(w,h)`；`diagonal = hypot(w,h)`；
  - `diameter = w*(1-diffRatio) + diagonal*diffRatio`。
- **旋转角度** = `atan2(右眼.y - 左眼.y, 右眼.x - 左眼.x)`（跟随头部倾斜）。
- 绘制：画布平移到圆心 → 旋转 → 以 `diameter` 为字号居中绘制 Emoji 文本（垂直方向按字体度量微调基线），支持自定义字体。

### 7.2 模糊遮挡区域

- **面部目标**：区域矩形 = 人脸框；角度 = 双眼角度。
- **眼部目标**：`眼距 = hypot(双眼)`，`宽 = 眼距 × 1.8`，`高 = 宽 × 0.5`，中心 = 双眼中点。
- 渲染统一裁剪为**旋转椭圆**（视觉更自然）：画布 `save → rotate(angle, 中心) → 椭圆 clip → 绘制处理后区域 → restore`。

### 7.3 三种模糊效果（算法）

统一思路：先把区域内容"逆旋转对齐"裁出小图，再处理，最后旋转贴回椭圆裁剪区。

1. **高斯模糊**：对小图做模糊（端侧优先用系统图像效果/着色器；纯软件实现用 **StackBlur**，O(n) 近似高斯）。半径随区域尺寸自适应。
2. **像素化**：把小图按 `pixelSize` 最近邻缩小再放大回原尺寸（关掉插值），形成马赛克块。`pixelSize` 随区域尺寸自适应。
3. **半色调**：按网格求每格平均色 → 生成块状底色 → 轻模糊过渡 → 按亮度绘制大小不一的圆点（奇偶行错位呈六边形点阵）。
4. **自适应单元尺寸**：`cellSize = hybrid(全局尺寸=max(W,H)/divisor, 区域尺寸=区域最大边/cells)`，区域权重约 0.8。三种效果使用不同 `divisor/cells` 调参。

### 7.4 命中检测（编辑选中）

- Emoji（圆形）：点到圆心距离 `< 直径/2`。
- 模糊（旋转椭圆）：把点平移到中心、反向旋转后，判断 `x²/a² + y²/b² ≤ 1`。

---

## 8. 数据模型与状态

### 8.1 领域模型（纯数据，便于序列化与单测）

- `FaceBox { x, y, width, height }`（原图空间）
- `FaceLandmarks { leftEye, rightEye, nose, mouthLeft, mouthRight }`
- `FaceDetection { id, box, landmarks, score }`
- `EmojiMask { id, centerX, centerY, diameter, originalDiameter, angle, emoji }`
- `BlurMask { id, rect, originalRect, angle }`
- `MaskKind = 'emoji' | 'blur'`
- `BlurEffect = 'gaussian' | 'pixelate' | 'halftone'`
- `BlurTarget = 'face' | 'eyes'`

### 8.2 编辑器状态（EditorViewModel）

- 图像：`originalPixelMap`（高清原图）、`displayPixelMap`（代理显示图）、`aspectRatio`。
- 检测：`detections`、`emojiMasks`、`blurMasks`。
- 模式：`maskKind`、`blurEffect`、`blurTarget`。
- 编辑态：`editingMaskId`、`editingDraft`（瞬时草稿，确认才写回）、`isAddMode`、`isProcessing`、`isExporting`、`isSliding`。
- 偏好（来自 Settings）：`emojiPalette`、`selectedFont`、`hideAppIcon`。

### 8.3 设置（Preferences 持久化）

`emojiPalette: string[]`、`fonts: string[]`、`selectedFont`、`hideAppIcon`、`defaultMaskKind`、`defaultBlurEffect`、`defaultBlurTarget`。

---

## 9. 关键交互流程

1. **导入**：从首页选图（PhotoPicker），或被其它应用以"分享图片"拉起（`want` 携带 uri）→ 进入编辑器。
2. **检测**：解码 → 生成显示图 → letterbox → 推理 → 解码+NMS → 按当前模式生成 Emoji/模糊遮挡。
3. **编辑**：点选某张脸 → 打开调整面板（Emoji：换表情/大小/角度；模糊：大小/角度）→ 确认写回 / 取消。
4. **新增**：进入"添加模式" → 点击图片任意位置新增一个遮挡对象。
5. **删除**：长按遮挡对象 → 二次确认。
6. **导出**：在原图上重渲染 → 保存到相册（写入软件 EXIF 标记）或经临时文件分享。

---

## 10. 设备适配策略（一多落地）

| 形态 | 断点 | 布局 |
|------|------|------|
| 手机竖屏 | sm | 顶部精简导航 + 中部画布 + 底部操作坞（模式分段 + 上下文工具条） |
| 平板/折叠/横屏 | md | 左画布(主) + 右侧属性检查器栏；导航置顶 |
| 平板横屏 / 2in1 | lg | 左画布(更大) + 右侧栏(工具+属性常驻)；支持鼠标/触控板悬停反馈 |

- 通过 `Navigation`(auto split) + `GridRow/GridCol` + 断点状态驱动同一页面的不同排布。
- 触控目标 ≥ 40vp；底部操作区保证单手可达。

---

## 11. 权限与持久化

- **图片读取**：优先使用 `PhotoViewPicker`（免敏感权限）。
- **保存相册**：使用相册写入能力（saveButton / 受控保存），写入 `Pictures/SkipFace`。
- **分享**：写临时文件后通过系统分享面板分享。
- **设置持久化**：`@ohos.data.preferences`。
- 全程不申请网络权限，强调离线隐私。

---

## 12. 可拓展性设计

- **遮挡策略可插拔**：新增效果只需实现 `MaskStrategy` 并在 `MaskRenderer` 注册。
- **检测器抽象**：`FaceDetector` 接口，`MindSporeFaceDetector` 为默认实现；未来可替换为系统视觉服务或其它模型而不动上层。
- **用例无状态**：领域用例纯函数化，便于复用与单测。
- **特性模块化**：editor / settings 可演进为独立 HSP，支持按需加载。

---

## 13. 里程碑

1. **M1 脚手架**：工程分层、断点系统、主题与资源、路由（Home/Editor/Settings 空壳）。
2. **M2 推理打通**：模型转换与加载、letterbox、推理、NMS，输出可视化检测框。
3. **M3 渲染引擎**：Emoji 渲染 + 模糊三效果 + 椭圆裁剪 + 命中检测（预览路径）。
4. **M4 编辑闭环**：增/删/改、调整面板、模式切换、设置持久化。
5. **M5 导出分享**：高清重渲染、相册保存、系统分享。
6. **M6 一多适配**：md/lg 双栏与属性检查器、深色主题、细节打磨。

---

## 14. UI 设计规范

详见同目录 Pencil 设计稿（`pencil-new.pen`）中的 **SkipFace 全新设计**。本次为**全新原创设计**，不沿用任何既有应用的布局范式，要点见下一节摘要，完整视觉以设计稿为准。

### 14.1 全新设计理念（与既有范式的区别）

本次 UI 为**原创重构**，刻意避开"顶部应用栏 + 一堆悬浮按钮 + 弹出底部表单"的旧范式，改为更专业、更贴合 HarmonyOS 的结构：

1. **独立首页（Landing）**：不再把"空状态"塞进编辑器，而是设计一个有隐私主张的首页（品牌、价值主张、隐私徽标、主/次入口）。
2. **导出动作上移**：保存/分享放到编辑页**顶部右侧**主操作位，符合 HarmonyOS"标题栏放主操作"的习惯，释放底部空间。
3. **统一底部操作坞（Dock）**：底部用一个抬升的圆角坞承载"模式分段 + 上下文工具条"，信息密度高、层级清晰，取代零散的悬浮按钮。
4. **专业深色画布**：编辑区使用深色背景聚焦照片，遮挡与选中态对比更强。
5. **设置改为整页**：分组卡片式整页设置，而非临时底部表单，便于扩展更多偏好项。
6. **大屏属性检查器**：平板/2in1 用右侧常驻 Inspector 承载工具与属性，避免在大屏上还用底部弹层。

### 14.2 设计令牌（Design Tokens）

| 类别 | 令牌 | 浅色 | 深色 | 说明 |
|------|------|------|------|------|
| 品牌 | `brand` | `#5B6CFF` | `#7C8AFF` | 主强调色（隐匿/科技感） |
| 品牌弱 | `brand_soft` | `#ECEEFF` | `#23264D` | 选中底/标签底 |
| 画布 | `canvas` | `#1B1C1F` | `#0E0F12` | 编辑区深色背景 |
| 背景 | `bg` | `#F5F6F8` | `#121316` | 页面背景 |
| 表面 | `surface` | `#FFFFFF` | `#1E2024` | 卡片/坞面 |
| 主文本 | `text` | `#1A1C1E` | `#ECECEC` | |
| 次文本 | `text_2` | `#6A7078` | `#9AA0A8` | |
| 分隔线 | `divider` | `#E8EAED` | `#2A2D32` | |
| 成功/保存 | `accent` | `#19B36B` | `#2BD080` | 导出成功反馈 |
| 危险 | `danger` | `#F5483B` | `#FF6257` | 删除 |
| 圆角 | `radius_l/m/s` | 24/16/10 | — | 卡片/控件/标签 |
| 间距 | `space` | 4 的倍数 | — | 8/12/16/24 |

- 字体：系统 HarmonyOS Sans（设计稿用 Noto Sans SC 近似）。标题 20–24、正文 14–16、辅助 12。
- 控件：胶囊按钮（圆角=高/2）、分段控制器、滑块、开关、分组列表行。

### 14.3 页面清单

1. **首页 HomePage**（sm/md/lg 自适应）
2. **编辑器 EditorPage（手机竖屏 sm）**：顶栏 + 深色画布 + 底部操作坞（表情/模糊两态）
3. **调整面板 Adjust Sheet**：半模态，大小/角度/表情
4. **设置 SettingsPage**：整页分组列表
5. **编辑器 EditorPage（平板/2in1 lg）**：双栏 + 右侧属性检查器
6. **删除确认 Dialog**

> 以上页面的完整视觉见 `pencil-new.pen`。代码实现时以设计令牌与栅格断点为准，禁止硬编码尺寸/颜色。

### 14.4 主题与明暗适配（代码层规范）

> **设计稿只产出"浅色"一套**（见 `pencil-new.pen`）。深色主题与主题色不在设计稿里重复绘制，而是**通过资源系统 + 语义令牌在代码层自动适配**。原则：UI 代码只引用"语义令牌"，绝不写死十六进制色值；浅/深由资源限定目录提供两套取值，主题色由可配置变量驱动。

#### 14.4.1 语义令牌 → 资源色

把 §14.2 的设计令牌全部落为**资源色**（`resources/base/element/color.json` 为浅色基线，`resources/dark/element/color.json` 为深色覆盖）。命名一律用"语义名"，不要用"颜色名"（用 `text_primary` 而非 `black`）。

`resources/base/element/color.json`（浅色，节选）：

```json
{
  "color": [
    { "name": "brand",        "value": "#5B6CFF" },
    { "name": "brand_soft",   "value": "#ECEEFF" },
    { "name": "brand_deep",   "value": "#3D4ED6" },
    { "name": "on_brand",     "value": "#FFFFFF" },
    { "name": "bg",           "value": "#F5F6F8" },
    { "name": "surface",      "value": "#FFFFFF" },
    { "name": "surface_2",    "value": "#F0F2F5" },
    { "name": "text_primary", "value": "#1A1C1E" },
    { "name": "text_secondary","value": "#6A7078" },
    { "name": "text_tertiary","value": "#9AA0A8" },
    { "name": "divider",      "value": "#E8EAED" },
    { "name": "accent",       "value": "#19B36B" },
    { "name": "danger",       "value": "#F5483B" },
    { "name": "scrim",        "value": "#80000000" }
  ]
}
```

`resources/dark/element/color.json`（深色，**同名覆盖**，系统按当前色彩模式自动选择）：

```json
{
  "color": [
    { "name": "brand",        "value": "#7C8AFF" },
    { "name": "brand_soft",   "value": "#23264D" },
    { "name": "brand_deep",   "value": "#AAB4FF" },
    { "name": "on_brand",     "value": "#0E0F12" },
    { "name": "bg",           "value": "#121316" },
    { "name": "surface",      "value": "#1E2024" },
    { "name": "surface_2",    "value": "#2A2D32" },
    { "name": "text_primary", "value": "#ECECEC" },
    { "name": "text_secondary","value": "#9AA0A8" },
    { "name": "text_tertiary","value": "#6A7078" },
    { "name": "divider",      "value": "#2A2D32" },
    { "name": "accent",       "value": "#2BD080" },
    { "name": "danger",       "value": "#FF6257" },
    { "name": "scrim",        "value": "#99000000" }
  ]
}
```

UI 中**只能**这样引用，禁止硬编码：

```typescript
// ✅ 正确：引用语义资源色，深浅自动切换
Text('SkipFace').fontColor($r('app.color.text_primary'))
Column().backgroundColor($r('app.color.surface'))

// ❌ 禁止：写死色值，无法适配深色 / 主题色
Text('SkipFace').fontColor('#1A1C1E')
```

> 说明：设计稿里编辑器用的是浅色画布。深色模式下，画布、表面、文本会通过上表的 `dark/` 覆盖自动变深，无需另画一套设计稿。"白底芯片/操作坞"在深色下自动变为 `surface`(#1E2024)，文本变 `text_primary`(#ECECEC)。

#### 14.4.2 明暗模式：跟随系统 + 应用内覆盖

支持三态：**跟随系统 / 强制浅色 / 强制深色**，存入 Preferences，启动时应用。

1. **跟随系统（默认）**：资源系统按系统色彩模式自动取 `base/` 或 `dark/`。监听 `AbilityStage`/`UIAbility` 的 `onConfigurationUpdate(config.colorMode)` 做即时刷新。
2. **应用内强制**：通过 `ApplicationContext.setColorMode()` 设置
   `ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT / _DARK / _NOT_SET(跟随系统)`。

```typescript
// common/theme/ThemeManager.ets （要点，详细注释见实现）
import { ConfigurationConstant } from '@kit.AbilityKit';

/** 主题模式：跟随系统 / 浅色 / 深色 */
export enum ThemeMode { System = 0, Light = 1, Dark = 2 }

export class ThemeManager {
  /** 应用持久化的主题模式到全局上下文；启动时与用户切换时调用 */
  static apply(ctx: common.ApplicationContext, mode: ThemeMode): void {
    const colorMode = mode === ThemeMode.Light ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : mode === ThemeMode.Dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET; // 跟随系统
    ctx.setColorMode(colorMode);
  }
}
```

3. **系统栏适配**：进入深色画布/浅色页面时，用 `window.setWindowSystemBarProperties` 同步状态栏前景色（深色背景用浅色图标，反之亦然），避免状态栏文字看不清。

#### 14.4.3 主题色（可配置强调色）

主题色 = `brand` 系列。两种支持级别，按需启用：

- **基础（必做）**：`brand / brand_soft / brand_deep / on_brand` 全部走资源色；换主题色只需改这组资源值，全 App 生效。
- **进阶（可选，动态换肤）**：提供"强调色可选"功能时，用 `AppStorageV2` 存一个 `brandColor`，并在根组件用 `@Builder`/自定义 `Theme` 注入；控件读取 `AppStorageV2` 的颜色而非静态资源。提供一组预设色板（如靛蓝/青绿/珊瑚），并保证每个预设都有浅/深两套取值与足够对比度（WCAG AA：正文对比度 ≥ 4.5:1）。

```typescript
// 进阶：可观察的主题色（动态换肤时使用）
import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
export class ThemePalette {
  @Trace brand: ResourceColor = $r('app.color.brand');
  @Trace brandSoft: ResourceColor = $r('app.color.brand_soft');
  // 切换预设时整体替换，UI 自动重渲染
}
export const themePalette = AppStorageV2.connect(ThemePalette, 'theme', () => new ThemePalette())!;
```

#### 14.4.4 编辑器画布的特殊说明

- 设计稿编辑器为**浅色画布**（`bg`/`surface_2`）。若后续产品决定编辑区固定深色（不随系统），应将其作为**独立的、与主题无关的"画布色"语义令牌**（如 `editor_canvas`）单独定义，而非复用 `bg`，以免和明暗适配冲突。**当前版本：编辑器画布跟随主题**（浅色态浅、深色态深），保持全局一致。
- 选中态高亮、遮挡描边统一用 `brand`，在深浅两套下都已保证可见度。

#### 14.4.5 检查清单（主题相关）

- [ ] 所有颜色均来自 `$r('app.color.*')`，无硬编码。
- [ ] `base/` 与 `dark/` 两份 `color.json` 令牌**同名同数量**。
- [ ] 三态主题（系统/浅/深）可切换并持久化。
- [ ] 系统状态栏前景色随主题切换。
- [ ] 文本/图标在深浅两套下对比度达 AA。
- [ ] 主题色集中在 `brand*` 一组，替换即全局生效。


---

## 15. 实现修订说明（v1.1，工程化落地）

本节记录代码落地阶段相对前文设计的修订，均为"保证开箱即用且正确"的工程决策。

### 15.1 人脸检测：默认改用 ONNX Runtime + YOLOv8-face（内置权重）

- 默认实现由 `OnnxFaceDetector` 提供，基于 OpenHarmony TPC 的 `@ohos/onnxruntime`
  （ONNX Runtime NAPI 移植），**直接加载 rawfile 内置的 YOLOv8-face 权重
  `skipface_face.onnx`**，端侧本地推理、开箱即用。与上游 Android 工程一致使用
  ONNX Runtime + YOLOv8-face 权重，免离线模型转换。
- 复用统一的 `Letterbox`（640×640 预处理）与 `DetectionDecoder`（解码 + NMS），
  输出人脸框 + 5 关键点（双眼/鼻/双嘴角），驱动遮挡跟随头部倾斜旋转。
- 模型契约：输入 `images` `[1,3,640,640]` Float32(CHW, 归一化)，输出 `output0`
  `[1,20,8400]`（cx,cy,w,h,score + 5 关键点(x,y,conf)）；运行时动态查询输入/输出名。
- 许可：YOLOv8-face 权重为 Ultralytics **AGPL-3.0**；`@ohos/onnxruntime` 随包提供
  arm64-v8a 预编译原生库。详见 `resources/rawfile/README.md`。
- **可选替换实现**保留并可在 `AppContainer.init()` 一行切换：
  - `CoreVisionFaceDetector`（系统 Core Vision Kit，免模型文件）；
  - `MindSporeFaceDetector`（系统 MindSpore Lite，需 `converter_lite` 转出 `.ms`）。
- 设备不支持（非 arm64 无原生库）或推理失败时优雅降级为"无自动检测"，用户仍可手动添加遮挡。

### 15.2 保存到相册：改用 SaveButton 安全控件（免静态权限）

- 编辑页"保存"改为系统 `SaveButton` 安全控件：点击即获一次性写入授权。
- 保存流程严格按"先 `createAsset`（消费授权窗口）→ 再高清导出 → 最后写入资源"的顺序，
  避免授权过期。已移除 `module.json5` 中的 `ohos.permission.WRITE_IMAGEVIDEO` 声明。

### 15.3 自定义字体：补全注册与选择链路

- 编辑页进入时通过 `UIContext.getFont().registerFont` 注册用户所选字体，并把族名透传给
  预览(`MaskOverlay`)与导出(`ImageExporter`)的 emoji 绘制。
- 设置页补全字体列表：可选择（打勾）、删除、新增。

### 15.4 启动时序、主题与系统栏

- `SkipfaceAbility.onWindowStageCreate` 现在 **await** 依赖容器初始化并应用主题后再 `loadContent`，
  消除分享冷启动时"容器未就绪"的竞态崩溃。
- 新增 `onConfigurationUpdate` 跟随系统色彩模式刷新，并用 `setWindowSystemBarProperties` 同步状态栏前景色。

### 15.5 性能与渲染稳定性

- `MaskOverlay` 增加重绘并发保护（重绘进行中标记 dirty，结束补绘），避免交错绘制闪烁。
- 拖动大小/角度滑块时，模糊预览降级为轻量椭圆占位（不跑像素算法），松手后再做一次高质量重绘，显著降低卡顿。

### 15.6 工程清理

- 移除未使用的 C++ 原生脚手架（`cpp/`、`libskipface.so` 依赖、`externalNativeOptions`、相关 mock）。
- "隐藏应用图标"在 HarmonyOS 普通应用上无公开 API 可实现，已从设置移除，改为真实的"全程本地处理"隐私说明行。
- 工程路径必须为纯 ASCII（仅字母/数字/`-_.()@`/空格）；含中文路径会触发 hvigor `00306003` 构建失败。
- 模块名由默认的 `entry` 重命名为 `skipfaceapp`，与工程命名保持一致风格（`build-profile.json5`、
  `oh-package.json5`、`module.json5` 三处同步；构建产物为 `skipfaceapp-default-*.hap`）。
  注：模块名不能与项目名 `skipface` 相同（DevEco 同步会报错），故取 `skipfaceapp`。
