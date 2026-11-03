# Wintermute Mobile

Wintermute 的 Flutter 移动端初步 demo，目标平台为 **Android / iOS**。已生成两个平台的原生工程。

深色主页包含问候、声音波形、今日概览、记忆切片和示例设备状态。支持底部导航、搜索与筛选记忆、查看详情、模拟聊天和设备说明。数据来自 `lib/data/demo_data.dart`，无需后端、账号或 API Key。模拟对话离开页面后清空；没有真实录音、配对、上传或存储功能。

## 运行

开发基线：Flutter **3.44.6 stable** / Dart **3.12.2**。请提交并使用 `pubspec.lock`。

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

Android 需要 Android Studio、Android SDK、Command-line Tools、对应 SDK 平台和已接受的 SDK licenses。用 `flutter doctor` 检查环境，在 Android Studio 创建并启动模拟器，或连接真机。

```sh
flutter build apk --debug
```

产物：`build/app/outputs/flutter-apk/app-debug.apk`。

iOS 需要 **macOS + Xcode**，安装所需 iOS Simulator runtime，然后运行：

```sh
open -a Simulator
flutter devices
flutter run -d <ios-simulator-id>
flutter build ios --simulator
```

真机安装需要在 Xcode 中打开 `ios/Runner.xcworkspace` 并配置开发团队。当前包名为 `dev.wintermute.wintermute_mobile`；正式发布前应确认包名、应用图标及签名。Android release 配置仍使用 Flutter 模板的 debug key，只用于开发，不能作为正式发布配置。

## 验证与结构

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Widget 测试覆盖 360px 手机、横屏、平板、放大字体，以及搜索、详情和模拟对话流程。UI 使用 SafeArea、可滚动内容、键盘避让和居中最大内容宽度。系统字体随 Android/iOS 平台选择，不依赖在线字体。

已配置 Android APK / iOS Simulator 的 CI 构建；需推送仓库后运行。iOS 的编译与真机效果仍需在 macOS 环境验证。

2026-10-31 本机验证：`flutter analyze`、4 项 Widget 测试、Android debug APK 构建通过；APK 已安装并在 Android 模拟器启动。当前本机 `flutter doctor` 仍提示 Android Command-line Tools 缺失，但已有 SDK 足以完成此次 debug 构建。

- `lib/main.dart`：入口、颜色与主题。
- `lib/screens/`：主页、记忆/设备导航和聊天页。
- `lib/widgets/shared.dart`：卡片、波形绘制、详情面板。
- `lib/data/demo_data.dart`：静态示例数据，后续服务接入点。
- `android/`、`ios/`：Flutter 生成的原生工程。

参考：[Flutter 平台支持](https://docs.flutter.dev/reference/supported-platforms)、[iOS 构建](https://docs.flutter.dev/deployment/ios)。
