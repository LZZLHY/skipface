# 人脸检测说明

## 当前实现：系统 Core Vision Kit（免模型文件）

本应用的人脸检测使用 **HarmonyOS 系统自带的 Core Vision Kit**
（`@kit.CoreVisionKit` 的 `faceDetector`），见
`capability/inference/CoreVisionFaceDetector.ets`：

- 完全本地、离线，符合"隐私优先、纯本地"的产品定位；
- **免模型文件、开箱即用**，无需随包分发任何第三方权重（因此本目录不含模型文件）；
- 系统服务运行于独立进程、随系统升级而优化；不在应用进程内加载第三方原生推理库，
  从根本上规避了以往在应用进程内跑 ONNX Runtime(NAPI) 时因 `session.Run` 抛出的
  C++ 异常逸出 NAPI 边界、导致整个进程 abort(SIGABRT) 的崩溃；
- 系统返回人脸框与三维姿态(yaw/pitch/roll)，本实现由"人脸框 + roll"合成 5 个关键点
  （双眼/鼻/双嘴角），驱动 Emoji / 模糊遮挡跟随头部倾斜(roll)旋转；
- 设备不具备系统人脸能力或检测失败时优雅降级为"无自动检测"，用户仍可手动添加遮挡。

## 扩展：替换检测实现

检测器通过统一抽象 `capability/inference/FaceDetector.ets` 解耦，上层（用例/状态层）
只依赖该接口。如需替换为自研模型或其它系统能力，只需：

1. 新增一个实现 `FaceDetector` 接口的类（`load` / `isLoaded` / `detect` / `release`）；
2. 在 `common/di/AppContainer.ets` 的 `init()` 中把
   `new CoreVisionFaceDetector()` 替换为你的实现即可，无需改动上层与渲染逻辑。

`detect()` 需返回"代理显示图坐标系"下、已按置信度过滤的 `FaceDetection` 列表
（`SCORE_THRESHOLD` 见 `common/constants/AppConstants.ets`）。
