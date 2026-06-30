# 人脸检测说明

## 默认实现：ONNX Runtime + YOLOv8-face（本目录内置权重）

当前版本默认使用 **ONNX Runtime**（OpenHarmony TPC 包 `@ohos/onnxruntime`）直接加载本目录
内置的 YOLOv8-face 权重 `skipface_face.onnx` 进行端侧本地推理，见
`capability/inference/OnnxFaceDetector.ets`：

- 完全本地、离线，符合"隐私优先、纯本地"的产品定位；
- **开箱即用，模型权重已随仓库内置**，无需额外下载或转换；
- 输出人脸框 + 5 关键点（双眼/鼻/双嘴角），用于驱动 Emoji / 模糊遮挡跟随头部倾斜旋转；
- 设备不支持（如非 arm64 环境无原生库）或推理失败时自动降级为"无自动检测"，
  用户仍可手动添加遮挡。

### 模型契约（YOLOv8n-face，Ultralytics 导出）

- 输入：名 `images`，形状 `[1,3,640,640]` Float32，CHW，归一化 0~1，letterbox 灰填充；
- 输出：名 `output0`，形状 `[1,20,8400]`（通道优先）：`0~3`=cx,cy,w,h；`4`=score；
  `5~19`=5 个关键点(x,y,conf)。
- 预处理见 `capability/inference/Letterbox.ets`，后处理（解码 + NMS）见
  `capability/inference/DetectionDecoder.ets`。

> 运行时输入/输出名通过 `session.GetInputNames()/GetOutputNames()` 动态查询，不写死。

### 模型来源与许可

- 模型为开源上游 **Ultralytics YOLOv8n-face**（`names: {0: 'face'}`，imgsz 640）。
- 许可：**AGPL-3.0**（Ultralytics）。仅以"模型权重"形式引入；如需商用分发，请遵循
  Ultralytics 的许可条款（或替换为自行训练 / 可商用许可的等价权重）。
- 原生推理库 `@ohos/onnxruntime` 为 Apache-2.0 / MIT，随包提供 arm64-v8a 预编译 `.so`。

## 可选实现一：系统视觉服务（Core Vision Kit，免模型文件）

`capability/inference/CoreVisionFaceDetector.ets` 基于 `@kit.CoreVisionKit` 的 `faceDetector`，
完全本地、免模型文件。启用方式：在 `common/di/AppContainer.ets` 的 `init()` 中把
`new OnnxFaceDetector(context)` 改为 `new CoreVisionFaceDetector()`。

## 可选实现二：MindSpore Lite（需离线转换 .ms）

`capability/inference/MindSporeFaceDetector.ets` 基于系统 `@kit.MindSporeLiteKit`，需要
`.ms` 模型。启用步骤：

1. 用 MindSpore Lite 的 `converter_lite` 把 `yolov8n-face.onnx` 转换为 `.ms`：

   ```
   converter_lite --fmk=ONNX --modelFile=yolov8n-face.onnx --outputFile=skipface_face
   ```

   把得到的 `skipface_face.ms` 放入本目录（`src/main/resources/rawfile/`）。

2. 在 `common/di/AppContainer.ets` 的 `init()` 中把 `new OnnxFaceDetector(context)`
   改为 `new MindSporeFaceDetector(context)`。

> 三种实现共享同一套 `FaceDetector` 抽象、`Letterbox` 预处理与 `DetectionDecoder` 后处理，
> 可在 `AppContainer` 中一行切换，互不影响上层。
