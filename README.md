# Wintermute Mobile

Flutter 移动端打开即进入持久会话，连接后会同步后端的对话历史。顶部的书签按钮可浏览和搜索示例记忆。

## 连接和使用

“连接与采集”顶部的“外观”默认跟随系统，也可以固定为浅色或深色。选择保存在本机，尚未连接服务和离线时都能更改。

1. 在后端为手机配置一个 HTTP 终端，默认 ID 为 `http-mobile`。需要与其他设备共享 Agent 时，将各端绑定到相同的服务端用户和会话。为每个端分配独立的终端 ID 和令牌。
2. 首次点“设置连接”，或进入右上角“连接与采集”。填写服务根地址、终端 ID 和令牌，点“验证并保存”。应用通过受认证的收件箱验证连接，将凭据写入 Android 加密存储或 iOS 钥匙串。
3. 在对话底部输入消息，点向上箭头发送。上一条仍在运行时可继续补充。网络中断后，未确认送达的消息可按原消息 ID 手动重试。
4. 在“连接与采集”中按需开启以下开关。每个终端单独保存选择，首次均为关闭。离线记录会在应用回到前台并联网后按原事件 ID 和发生时间续传。关闭某一项会清除该项待发的记录。

- **记录应用活动**分享 Wintermute 自己的前后台和页面变化。系统挂起或强制结束时，最后一次切换可能来不及保存。
- **地点变化**使用 Android 或 iOS 的系统定位。使用期间授权可记录前台的位置，另授后台定位后可在系统允许时接收位置变化。Android 低频请求位置，iOS 在后台使用地点访问和显著位置变化服务。系统可能延迟投递；强制停止后需要重新打开应用。
- 定位后可在手机上把当前位置命名为“公司”等地点，也可移除名称。命名需要最近 15 分钟内、误差在 250 米以内的定位。应用在本机按约 250 米半径匹配，向 `POST /v1/perceptions` 发送 `mobile.location`，例如“到达「公司」”。未命名的位置发送保留两位小数的经纬度，约为公里级网格。连续相同的位置只发一次。
- **其他 App 使用时段**需要在 Android 系统中授予“使用情况访问权”。手机按系统的前后台事件估算已结束的使用时段，把应用显示名称（无法取得时用包名）、起止时间和时长作为文字切片发送至 `POST /v1/slices`。开始范围从开启并授权后算起。切换回 Wintermute 时会读取近期系统事件并补传。iOS 不提供这个开关对应的跨应用使用明细。
- **定时截屏**在用户确认系统屏幕共享后启用，默认每 5 分钟截一张，也可选 1 或 15 分钟。Android 需先开启“其他 App 使用时段”，JPEG 会携带前台应用、采集时间和对应时段 ID。iOS 使用系统屏幕共享选择器，在 Wintermute 处于后台时采样，不推断画面属于哪个应用。系统结束共享后，需要手动重新开启。图片暂存在本机，客户端收到后端入库回执后删除缓存。关闭开关或切换终端会清理待传截图。
  Android 最多缓存 32 张，iOS 最多缓存 64 张。队列满后保留已有截图，等上传腾出空间后继续采集。

手机打开、回到前台及停留在前台期间都会从后端读取当前会话。对话中能看到其他设备发送的消息和主 Agent 对日程等后台通知的回复。后端清空后，下一次成功同步会清除对话中的历史消息。本机保留未确认送达的草稿供手动重试。

## 安卓通知与附件

安卓端右上角的铃铛打开当前设备的通知收件箱。进入通知详情后会标记已读；每个附件显示文件名和大小，点选并确认系统保存位置后才下载。已过期的通知仍可在收件箱中查看。此前端连接旧版后端时，收件箱会提示需要更新后端。

应用在前台每 4 秒检查新通知。点收件箱的“允许系统提醒”后，后台会通过 Android 系统调度器在有网络时检查（周期约 15 分钟起）。省电策略可能进一步推迟检查，返回前台会再次同步。点系统提醒可直接打开相应通知。设备令牌保存在系统安全存储中。

## 开发运行

使用 Flutter 3.44.6、Dart 3.12.2 和仓库中的 `pubspec.lock`。

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
flutter build apk --debug
```

Android 模拟器访问开发机服务可用 `http://10.0.2.2:<端口>`，也可用 `adb reverse tcp:<端口> tcp:<端口>` 后连接 `http://127.0.0.1:<端口>`。Android debug 构建允许局域网 HTTP，正式环境使用 HTTPS。调试 APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。

iOS 工程使用相同的 Flutter 界面与协议、Keychain 和局域网用途说明。用 macOS、Xcode 和 iOS 模拟器运行 `flutter build ios --simulator`，真机需配置签名。Windows 环境只能验证 Android 设备流程。

iOS 真机签名时将 Runner 和 WintermuteBroadcast 两个目标加入同一个 App Group（`group.dev.wintermute.wintermuteMobile.screenshots`）。旧版 iOS 的屏幕广播扩展使用该共享容器暂存截图，供主应用恢复运行时上传。

## 验证

```sh
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

`integration_test/meeting_test.dart` 在设备上通过真实页面配置连接、开启活动采集，并通过对话询问会议安排。运行前启动测试后端，并用测试专用终端绑定。该测试会写入该终端所属的会话，并接收、确认该终端的输出。可用 `AGENT_EXPECT_REPLY` 检查确定性测试模型的回复片段。

```sh
flutter test integration_test/meeting_test.dart -d <device-id> --dart-define=AGENT_TEST_URL=<url> --dart-define=AGENT_TEST_TOKEN=<test-token> --dart-define=AGENT_TEST_TERMINAL=http-mobile
```
