# JsxposedX

- 英文文档：[`README_EN.md`](README_EN.md)
- 默认 README：[`README.md`](README.md)
- 发布版本：[`Download`](https://jsxposed.org)

JsxposedX 是一个面向 Xposed/LSPosed 和 Frida 工作流的 Flutter Android 应用。它把 Flutter UI 层、Android 侧的 Xposed Hook、LSPosed service 集成、原生 bridge 模块、共享 IDE 运行配置，以及 PowerShell 安装调试脚本放在同一个仓库里。



本项目长期坚持免费开源共享，旨在降低学习门槛，推动技术正向交流

本项目为开源技术研究工具，仅用于 软件调试、程序分析、内存机制学习、开发测试及授权环境研究 等合法用途。

作者开发并公开本项目的目的在于促进技术交流与学习，不针对任何特定游戏、平台、软件或在线服务，不提供任何作弊支持、绕过保护支持或违规使用指导。

严禁用于以下行为：
•	网络游戏作弊、外挂制作、自动化违规操作
•	干扰服务器或客户端正常运行
•	未经授权修改第三方程序数据
•	破坏公平竞争环境
•	任何违反法律法规或平台规则的用途

责任说明：

使用者应自行确保其使用行为符合所在地法律法规及相关服务条款。因使用、传播、二次开发本项目产生的任何直接或间接后果，由使用者自行承担，与作者无关。

开源说明：

本项目源代码公开不代表鼓励滥用行为。任何第三方基于本项目进行的修改、分发、商业化、非法用途，均与原作者立场无关。

作者保留权利：

作者有权拒绝提供任何违规用途支持，并可随时调整、暂停或终止项目公开内容。

继续使用本项目，即视为已阅读并同意本声明。

AI 功能定位

本项目内置 AI 功能仅作为通用智能辅助模块使用，主要用于数据分析、内容解释、结果筛选、信息整理、操作指引及学习研究等场景，用于提升用户使用效率与体验。

AI 功能属于辅助性服务，不直接参与任何目标程序的运行控制、数据破坏、权限绕过、作弊执行或其他违规操作。

内置接口说明

为方便用户使用，本项目提供默认 AI 接口接入服务。用户亦可根据自身需求，自行配置并使用合法取得的第三方 AI 服务接口，本项目不作强制限制。

费用说明

如部分 AI 功能涉及服务器资源、模型调用成本、算力消耗或接口费用，项目方可能对相关服务收取合理成本费用。该费用仅对应 AI 服务资源消耗，不代表对任何违规用途提供支持或收费。

输出免责说明

AI 输出内容基于模型自动生成，可能存在误差、遗漏、不准确或不适用于特定场景的情况，仅供参考。用户应自行判断并承担最终使用责任。

使用规范

严禁利用本项目 AI 功能从事以下行为：
•	外挂制作、作弊辅助、自动化违规操作
•	破解、攻击、干扰第三方系统
•	侵害他人合法权益
•	违反法律法规及平台规则的行为

责任归属

用户基于本项目 AI 功能实施的任何行为及产生的一切后果，由用户自行承担，与项目作者无关。

作者立场

作者始终倡导 AI 技术用于合法、正当、积极的学习研究与效率提升场景，反对任何滥用行为。
## 项目概览

- 应用名：`JsxposedX`
- 语言：英文、简体中文
- 主标签页：`Home`、`Project`、`Repository`、`Settings`
- Home 状态卡片：`AI`、`Root`、`Xposed`、`Frida`、`Zygisk module`
- Project 入口：`Quick Functions`、`AI Reverse`、`Xposed Project`、`Frida Project`

## 主要功能

- Xposed 项目页、代码编辑页、可视化编辑页
- Frida 项目页、脚本管理、目标开关、Hook 打包、编辑页
- AI Reverse 页面，包含 AI 对话、APK 上下文和 SO 分析工具
- Quick Functions 常用 Hook 开关
- Crypto audit log 和 JS editor
- SO analysis 页面，包含 `ELF Info`、`Exports`、`Imports`、`JNI`、`Strings`、`Sections`
- 内置文档位于 `assets/raws/JsxposedX_API.md`、`assets/raws/JsxposedX_API_en.md`、`assets/raws/Frida_API.md`、`assets/raws/Frida_API_en.md`
- `Repository` 标签页当前还是占位页

## 相关仓库

- Frida 模块仓库：[`dugongzi/jsxposedx-frida`](https://github.com/dugongzi/jsxposedx-frida)

## Quick Functions

当前代码里的 quick-function key：

- `injectTip`
- `removeScreenshotDetection`
- `removeDialogs`
- `removeCaptureDetection`
- `modifiedVersion`
- `hideXposed`
- `hideRoot`
- `hideApps`
- `algorithmicTracking`

## 为什么构建和调试流程不同于普通 Flutter App

这个仓库不只是 Flutter UI 项目。

- `android/app/src/main/AndroidManifest.xml` 声明了 Xposed 模块元数据
- `android/app/src/api100/` 和 `android/app/src/api101/` 各自维护一套很薄的 Xposed 壳
- `android/app/src/api100/assets/xposed_init` 指向 `com.jsxposed.x.MainHook`
- `android/app/src/api100/resources/META-INF/xposed/module.prop` 对应 `api100`
- `android/app/src/api101/resources/META-INF/xposed/module.prop` 对应 `api101`
- `android/app/src/main/` 只保留 Flutter UI、共享 Hook 核心和原生 bridge
- `android/app/src/main/kotlin/com/jsxposed/x/App.kt` 初始化 LSPosed service
- `android/app/src/main/kotlin/com/jsxposed/x/NativeProvider.kt` 注册了 `Pinia`、`StatusManagement`、`App`、`Project`、`ApkAnalysis`、`SoAnalysis`、`LSPosed`、`ZygiskFrida` 这些原生 bridge 模块

所以安装和验证流程会同时涉及 Android/Xposed 侧与 Flutter 侧。

## 环境要求

- Flutter SDK
- Android SDK 与 `adb`
- Windows PowerShell，仓库里的共享脚本基于它
- 用于 Xposed/LSPosed 流程的 root 测试环境
- 用于 Frida 流程的 Zygisk/Frida 环境

## 关键目录

- `lib/`：Flutter UI、路由、provider、功能页面
- `lib/pigeons/`：Pigeon bridge 定义
- `lib/generated/`：生成出来的 Dart bridge 代码
- `android/app/src/main/kotlin/com/jsxposed/x/`：共享 Android 代码、Hook 核心、原生 bridge 实现
- `android/app/src/api100/`：`api100` 壳、入口类与模块资源
- `android/app/src/api101/`：`api101` 壳、入口类与模块资源
- `.buildScript/`：代码生成与 Debug 安装的共享 PowerShell 脚本
- `.idea/runConfigurations/`：共享 IDE 运行配置

## 共享 IDE 运行配置

这个仓库提交了 `.idea/runConfigurations/`。

拉取仓库后，JetBrains IDE 可以加载这些共享运行配置：

- `watch_pigeons` -> 执行 `.buildScript/pigen_watch.ps1`
- `build_for_xposed_type` -> 执行 `.buildScript/run_install_debug.ps1 -SkipAttach`

## Pigeon 代码生成

`.buildScript/pigen_watch.ps1` 会监听 `lib/pigeons/**/*.dart`，并且：

- 生成 Dart bridge 文件到 `lib/generated`
- 生成 Kotlin bridge 文件到 `android/app/src/main/kotlin/...`
- 当 `*NativeImpl.kt` 不存在时创建模板文件

在仓库根目录运行：

```powershell
.\.buildScript\pigen_watch.ps1
```

## Debug 安装脚本

`.buildScript/run_install_debug.ps1` 是当前仓库里的 Debug 安装脚本。

它会：

- 默认执行 `:app:installDebug`，这个任务已映射到 `api100Debug`
- 把 `pubspec.yaml` 里的 `versionName` 和 `versionCode` 同步到 `android/local.properties`
- 从 `-DeviceId`、`ANDROID_SERIAL`、Android Studio 当前选中设备或单个已连接 `adb` 设备中解析目标设备
- 安装完成后等待一段时间，给包替换广播和 LSPosed 重扫留时间
- 可以执行 force-stop、启动应用以及 `flutter attach`

在仓库根目录运行：

```powershell
.\.buildScript\run_install_debug.ps1
```

常用参数：

```powershell
.\.buildScript\run_install_debug.ps1 -SkipAttach
.\.buildScript\run_install_debug.ps1 -SkipLaunch
.\.buildScript\run_install_debug.ps1 -DeviceId <serial>
.\.buildScript\run_install_debug.ps1 -GradleTask :app:installApi101Debug
```

补充说明：

- `installDebug` / `assembleDebug` 默认仍然走 `api100`
- 要安装 `api101` 壳，请显式传 `-GradleTask :app:installApi101Debug`

这个脚本用于 Xposed/LSPosed 的 Debug 安装流程，不是普通 Flutter hot reload 的替代品。

## 常规构建

Flutter 常规构建命令仍然可以直接使用：

```powershell
flutter build apk --debug
flutter build apk --release
flutter build apk --flavor api100 --release
flutter build apk --flavor api101 --release
flutter build appbundle --flavor api100 --release
flutter build appbundle --flavor api101 --release
```

如果你需要 `api101` 的 release APK，可以直接运行：

```powershell
flutter build apk --flavor api101 --release
```

输出文件通常在：

```text
build/app/outputs/flutter-apk/app-api101-release.apk
```

如果要直接构建某个 Xposed 壳，建议优先使用 Gradle 任务：

```powershell
cd android
.\gradlew.bat :app:assembleApi100Debug
.\gradlew.bat :app:assembleApi101Debug
.\gradlew.bat :app:assembleApi100Release
.\gradlew.bat :app:assembleApi101Release

cd android
.\gradlew.bat :app:bundleApi100Release
.\gradlew.bat :app:bundleApi101Release

```

两类命令的区别：

- `flutter build apk --flavor api101 --release`：从 Flutter CLI 进入，最终生成对应 flavor 的 release APK，例如 `build/app/outputs/flutter-apk/app-api101-release.apk`
- `flutter build appbundle --flavor api100 --release`：从 Flutter CLI 进入，先处理 Flutter/Dart 资源与插件，再调用对应的 Android Gradle 变体任务
- `.\gradlew.bat :app:bundleApi100Release`：直接从 Android Gradle 进入，更适合排查 flavor、Xposed 壳、资源合并和原生构建问题
- `.\gradlew.bat :app:assembleApi101Release`：直接从 Android Gradle 进入，适合只想拿对应 flavor 的 release APK
- 对同一个 flavor 来说，这两种命令最终目标的 Android 产物是一致的，例如 `api100` 对应 `bundleApi100Release`

`.buildScript/run_install_debug.ps1` 负责设备侧的安装、启动和 attach 流程。

## Release 签名

Release 签名通过本地 `android/key.properties` 加载。

- `android/key.properties` 不在仓库中
- keystore 文件不在仓库中
- 签名信息只保留在本地文件中

## 常见开发流程

```powershell
flutter pub get
.\.buildScript\pigen_watch.ps1
.\.buildScript\run_install_debug.ps1
flutter attach
```

安装完成后，再到设备侧做 LSPosed/Xposed 或 Zygisk/Frida 验证。

## 桌面端（通过 USB 控制手机）

仓库支持把整套界面搬到电脑上运行：**UI 与业务逻辑仍复用 `lib/` 下的同一份代码，原生能力通过 USB 由手机执行**，所以桌面端与手机端的功能和结论保持一致。

- 架构与协议说明：[`docs/desktop_bridge_CN.md`](docs/desktop_bridge_CN.md)
- 桌面端入口：`lib/desktop/main_desktop.dart`
- 手机侧服务：`android/app/src/main/kotlin/com/jsxposed/x/core/desktop_bridge/`
- 一键启动脚本（开发调试，支持热重载）：

```powershell
# 自动完成 adb forward、读取令牌、启动桌面端
.\.buildScript\run_desktop_bridge.ps1
```

- 打可分发的 exe（release）：

```powershell
# 产出 build/desktop/JsxposedX/JsxposedX.exe 与同名 zip，
# 并会把 adb 一并打进 platform-tools 目录，所以双击 exe 就能自己连手机
.\.buildScript\build_desktop_exe.ps1
```

原理简述：桌面端把 `dev.flutter.pigeon.JsxposedX.*` 的 Pigeon 通道原样隧道到手机上，由手机 App 内已注册的 Pigeon Handler 执行（104 个方法无需逐个适配）。宽屏（最大化窗口）下界面走侧边导航与双栏布局。

## 说明

- 当前仓库里的共享脚本都是 PowerShell 脚本。
- 如果不是 Windows 环境，就按相同步骤手动执行。
- `flutter run` 仍然可以用于普通 Flutter 迭代，这个仓库另外保留了 Android/Xposed 的安装验证流程。
