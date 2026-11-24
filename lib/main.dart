import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/chat_screen.dart';
import 'data/mobile_session.dart';
import 'data/mobile_store.dart';
import 'data/mobile_signals.dart';
import 'data/device_inbox.dart';
import 'data/agent_api.dart';
import 'widgets/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const WintermuteApp());
}

@pragma('vm:entry-point')
Future<void> usageWorker() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.wintermute/usage_worker');
  final store = DeviceStore();
  final api = AgentApi();
  var retrySeconds = 0;
  while (true) {
    var delay = const Duration(seconds: 2);
    try {
      final next = await channel.invokeMapMethod<String, dynamic>('next');
      if (next != null) {
        final conn = await store.connection();
        final row = Json.from(next['row'] as Map);
        final body = row['source'] == 'location'
            ? LocationFix.fromRecord(row)?.perception(
                row['id'] as String,
                DateTime.fromMillisecondsSinceEpoch(
                  row['at'] as int,
                  isUtc: true,
                ),
              )
            : AppUsage.fromRecord(row)?.perception;
        final key = {
          'scope': next['scope'],
          'id': row['id'],
          'source': row['source'],
          'withFrame': row['hasVisitScreenshot'] == true,
        };
        final frame = row['hasVisitScreenshot'] == true
            ? await channel.invokeMapMethod<String, dynamic>('visitFrame', key)
            : null;
        if (conn != null &&
            conn.scope == next['scope'] &&
            body != null &&
            (row['hasVisitScreenshot'] != true || frame != null) &&
            await channel.invokeMethod<bool>('canSend', key) == true) {
          final receipt = frame == null
              ? await api.request(conn, AppUsage.path, body: body)
              : await api.uploadAppVisit(conn, body, frame);
          if (receipt['event_id'] is! String) {
            throw const FormatException('缺少使用时段回执');
          }
          await channel.invokeMethod<void>('ack', key);
          delay = Duration.zero; // Drain already completed intervals in order.
        }
      }
      retrySeconds = 0;
    } catch (_) {
      retrySeconds = retrySeconds == 0 ? 2 : (retrySeconds * 2).clamp(2, 60);
      delay = Duration(seconds: retrySeconds);
    }
    await Future<void>.delayed(delay);
  }
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
