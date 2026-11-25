import 'dart:io';
import 'package:flutter/services.dart';
import 'agent_api.dart';

enum ConnectorPlatform {
  android('Android'),
  ios('iOS'),
  unsupported('');

  const ConnectorPlatform(this.label);
  final String label;
  static const mobile = [android, ios];
  static ConnectorPlatform get current => Platform.isAndroid
      ? android
      : Platform.isIOS
      ? ios
      : unsupported;
  List<ConnectorPlatform> get displayOrder =>
      this == ios ? const [ios, android] : mobile;
  Iterable<MobileConnector> get catalog =>
      MobileConnector.values.where((item) => item.platform == this);
}

enum MobileConnector {
  clock('android_clock', '闹钟和计时器', '通过系统时钟设置闹钟或开始倒计时。', [
    'android_set_alarm',
    'android_start_timer',
  ]),
  usage('android_usage', '安卓使用时间', '按应用汇总最近几天的前台使用时间。', ['android_app_usage']),
  calendar('android_calendar', '安卓日历', '查看系统日程，或打开日历确认新日程。', [
    'android_calendar_events',
    'android_calendar_create',
  ]),
  contacts('android_contacts', '通讯录', '按姓名查找联系人的号码和邮箱。', ['android_contacts']),
  files('android_files', '安卓文件系统', '浏览所选目录，分段读取文本文件。', [
    'android_files_list',
    'android_files_read',
  ]),
  location('android_location', '安卓位置', '查询一次当前位置、定位时间和误差。', [
    'android_location',
  ]),
  notifications('android_notifications', '通知', '读取当前通知栏中的来源、标题和摘要。', [
    'android_notifications',
  ]),
  sms('android_sms', '短信', '按关键词查找短信号码、时间和正文片段。', ['android_sms']),
  iosCalendar('ios_calendar', 'Apple Calendar', '查询系统日程，或把会议加入日历。', [
    'ios_calendar_events',
    'ios_calendar_create',
  ]),
  iosContacts('ios_contacts', 'Apple Contacts', '在已授权的联系人中按姓名查找电话和邮箱。', [
    'ios_contacts',
  ]),
  iosHealth('ios_health', 'Apple Health', '在本机汇总步数、睡眠和锻炼。每次由你确认后才向当前服务分享摘要。', [
    'ios_health_summary',
  ]),
  iosMusic(
    'ios_music',
    'Apple Music',
    '搜索 Apple Music 曲库，播放歌曲、切歌或调整进度。需要 iOS 15 或更新版本。',
    ['ios_music_search', 'ios_music_control'],
  ),
  iosPhotos('ios_photos', 'Photos', '按日期和类型查找已授权照片，返回拍摄时间、尺寸和编号，可在本机预览。', [
    'ios_photos_search',
    'ios_photo_open',
  ]),
  iosReminders('ios_reminders', 'Apple Reminders', '列出未完成待办，创建带提醒时间的事项或标为完成。', [
    'ios_reminders_list',
    'ios_reminders_create',
    'ios_reminders_complete',
  ]),
  iosLocation('ios_location', 'iPhone Location', '获取一次位置、定位时间和误差范围。', [
    'ios_location',
  ]);

  const MobileConnector(this.id, this.title, this.description, this.tools);
  final String id, title, description;
  final List<String> tools;
  ConnectorPlatform get platform =>
      id.startsWith('ios_') ? ConnectorPlatform.ios : ConnectorPlatform.android;
  String get key => id.substring(id.indexOf('_') + 1);
}

class MobileConnectors {
  MobileConnectors([ConnectorPlatform? platform])
    : platform = platform ?? ConnectorPlatform.current;
  final ConnectorPlatform platform;
  MethodChannel get _channel =>
      MethodChannel('dev.purin/${platform.name}_connectors');

  Future<Map<String, bool>> access(String scope) async =>
      platform == ConnectorPlatform.unsupported
      ? {}
      : (await _channel.invokeMapMethod<String, bool>('access', {
              'scope': scope,
            })) ??
            {};

  Future<bool> authorize(MobileConnector item, String scope) async =>
      item.platform == platform &&
      (await _channel.invokeMethod<bool>('authorize', {
            'id': item.key,
            'scope': scope,
          }) ??
          false);

  Future<void> releaseFolder(String scope) async {
    if (platform == ConnectorPlatform.android) {
      await _channel.invokeMethod<void>('releaseFolder', {'scope': scope});
    }
  }

  Future<Json> execute(
    String scope,
    String tool,
    Json args,
    int timeout,
  ) async {
    if (!platform.catalog.any((item) => item.tools.contains(tool))) {
      throw UnsupportedError('此工具不适用于当前设备');
    }
    final result = await _channel.invokeMapMethod<String, dynamic>('execute', {
      'scope': scope,
      'tool': tool,
      'args': args,
      'timeout': timeout,
    });
    if (result == null) throw StateError('设备未返回结果');
    return result;
  }
}
