import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/chat_screen.dart';
import 'data/mobile_session.dart';
import 'data/mobile_store.dart';
import 'data/device_inbox.dart';
import 'data/agent_api.dart';
import 'widgets/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WintermuteApp());
}

@pragma('vm:entry-point')
Future<void> notificationJob() async {
  WidgetsFlutterBinding.ensureInitialized();
  var retry = false;
  try {
    final conn = await DeviceStore().connection();
    if (conn != null) {
      await receiveNotices(
        AgentApi(),
        conn,
        (notice) async =>
            await noticeChannel.invokeMethod<bool>('post', {
              'scope': conn.scope,
              'id': notice.id,
              'title': notice.title,
              'body': notice.body,
            }) ??
            false,
        active: () => true,
      );
    }
  } on ApiError catch (e) {
    retry = e.status >= 500;
  } catch (_) {
    retry = true;
  }
  await noticeChannel.invokeMethod<void>('finished', {'retry': retry});
}

class WintermuteApp extends StatefulWidget {
  const WintermuteApp({super.key, this.session});
  final MobileSession? session;
  @override
  State<WintermuteApp> createState() => _WintermuteAppState();
}

class _WintermuteAppState extends State<WintermuteApp>
    with WidgetsBindingObserver {
  late final session =
      widget.session ?? MobileSession(DeviceStore(), AgentApi());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final binding = WidgetsBinding.instance;
    binding.deferFirstFrame();
    session.restoreTheme().whenComplete(binding.allowFirstFrame);
    session.page('Agent 对话');
    session.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) session.foreground(true);
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      session.foreground(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: session.themeMode,
    builder: (context, mode, child) => MaterialApp(
      title: 'Wintermute',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: mode,
      themeAnimationDuration: Duration.zero,
      builder: (context, page) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: barsFor(Theme.of(context).colorScheme),
        child: page!,
      ),
      home: child,
    ),
    child: ChatScreen(session: session),
  );
}

final _lightTheme = terminalTheme(lightColors);
final _darkTheme = terminalTheme(darkColors);
