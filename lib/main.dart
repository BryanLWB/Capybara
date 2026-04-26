import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/generated/app_localizations.dart';
import 'screens/auth_screen.dart';
import 'screens/web_payment_return_page.dart';
import 'screens/root_shell.dart';
import 'screens/web_auth_page.dart';
import 'screens/web_shell.dart';
import 'models/web_payment_return_data.dart';
import 'services/api_config.dart';
import 'services/remote_config_service.dart';
import 'services/tray_service.dart';
import 'services/unified_vpn_service.dart';
import 'services/user_data_service.dart';
import 'services/panel_api.dart';
import 'services/v2ray_service.dart';
import 'theme/app_theme.dart';
import 'utils/asset_utils.dart';
import 'utils/web_boot_ready.dart';
import 'widgets/capybara_splash.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _registerExitCleanup();

  // Load persisted TUN mode state
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await V2rayService().loadTunState();
  }

  // 初始化资源文件（复制 geoip.dat/geosite.dat 到文件目录）
  if (!kIsWeb && Platform.isAndroid) {
    // 只有 Android 需要手动复制到 filesDir 给 native 层使用
    // Desktop 端直接通过 Process 运行二进制，二进制会自动找同级目录的 dat
    // 或者我们在 desktop_proxy_service 已经处理了
    await AssetUtils.copyAssets();
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    // 初始化托盘 (确保图标尽早显示)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await TrayService.instance.init(
          onShowWindow: () async {
            await windowManager.show();
            await windowManager.focus();
          },
        );
      } catch (e) {
        debugPrint('[Main] Tray init error: $e');
      }
    }

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1000, 720),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'Capybara',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();

      // 设置窗口图标
      try {
        if (Platform.isLinux || Platform.isWindows) {
          final exePath = Platform.resolvedExecutable;
          final exeDir = File(exePath).parent.path;
          final assetPath = Platform.isWindows
              ? 'assets/icons/app_icon.ico'
              : 'assets/icons/app_icon.png';

          // 尝试构建后的路径
          String iconPath = '$exeDir/data/flutter_assets/$assetPath';
          if (!await File(iconPath).exists()) {
            // 开发环境回退
            iconPath = assetPath;
          }

          if (await File(iconPath).exists()) {
            await windowManager.setIcon(iconPath);
          }
        }
      } catch (e) {
        debugPrint('[Main] Error setting icon: $e');
      }
    });
  }

  runApp(const CapybaraApp());
}

Future<void> _registerExitCleanup() async {
  if (kIsWeb) return;
  final vpn = UnifiedVpnService.instance;

  // Windows: 使用 WindowListener 监听窗口关闭事件
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    windowManager.addListener(_AppCloseListener(vpn));
  }

  // Unix: 捕获退出信号
  if (!Platform.isWindows) {
    for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      sig.watch().listen((_) async {
        try {
          await vpn.disconnect();
        } catch (_) {}
        exit(0);
      });
    }
  }
}

/// 监听窗口关闭事件，确保清理 TUN 和代理进程
class _AppCloseListener extends WindowListener {
  final UnifiedVpnService vpn;
  _AppCloseListener(this.vpn);

  @override
  void onWindowClose() async {
    debugPrint('[AppCloseListener] Window closing, cleaning up...');
    try {
      await vpn.disconnect();
      debugPrint('[AppCloseListener] VPN disconnected');
    } catch (e) {
      debugPrint('[AppCloseListener] Disconnect error: $e');
    }

    // 强制清理 sing-box 进程（TUN 网卡由 sing-box 自动清理）
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/F', '/IM', 'sing-box.exe']);
      } catch (_) {}
    }

    await windowManager.destroy();
  }
}

class CapybaraApp extends StatelessWidget {
  const CapybaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Capybara',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      // 多语言配置
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _api = PanelApi();
  final _config = ApiConfig();
  bool _authed = false;
  bool _isChecking = true;
  bool _webReadyMarked = false;
  WebPaymentReturnData? _paymentReturnData;
  final _startTime = DateTime.now();

  // Web 端优先首屏可见，桌面端保持原有开屏节奏。
  static const _desktopMinSplashDuration = 2500;
  static const _webMinSplashDuration = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _paymentReturnData = WebPaymentReturnData.tryParse(Uri.base);
      if (_paymentReturnData != null) {
        _isChecking = false;
        _scheduleWebReady();
        return;
      }
    }
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await _config.refreshSessionCache();
    final session = await _config.getSessionToken();

    if (session == null || session.isEmpty) {
      if (await _config.hasLegacyAuth()) {
        await _config.clearAuth();
      }
      await _finishAuthCheck(false);
      return;
    }

    if (kIsWeb) {
      await _finishAuthCheck(true);
      return;
    }

    var authResult = false;
    try {
      await _api.getUserInfo();
      authResult = true;

      try {
        await Future.wait([
          RemoteConfigService().getActiveDomain(),
          UserDataService().getNotices(),
        ]);
        debugPrint('[AuthGate] Data preloaded successfully');
      } catch (e) {
        debugPrint('[AuthGate] Preload failed: $e');
      }
    } catch (_) {
      await _config.clearAuth();
      authResult = false;
    }

    await _finishAuthCheck(authResult);
  }

  Future<void> _finishAuthCheck(bool authResult) async {
    final minSplashDuration =
        kIsWeb ? _webMinSplashDuration : _desktopMinSplashDuration;
    final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsed < minSplashDuration) {
      await Future.delayed(
        Duration(milliseconds: minSplashDuration - elapsed),
      );
    }

    if (mounted) {
      setState(() {
        _authed = authResult;
        _isChecking = false;
      });
      _scheduleWebReady();
    }
  }

  void _scheduleWebReady() {
    if (!kIsWeb || _webReadyMarked) return;
    _webReadyMarked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      markWebFlutterReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && _paymentReturnData != null) {
      return WebPaymentReturnPage(data: _paymentReturnData!);
    }
    // 检查中显示 Flutter 启动动画
    if (_isChecking) {
      if (kIsWeb) {
        return const _WebStartupPlaceholder();
      }
      return const CapybaraSplash();
    }
    if (!_authed) {
      if (kIsWeb) {
        return WebAuthPage(
          onAuthed: () => setState(() => _authed = true),
        );
      }
      return AuthScreen(
        onAuthed: () => setState(() => _authed = true),
      );
    }
    if (kIsWeb) {
      return WebShell(
        onLogout: () => setState(() => _authed = false),
      );
    }
    return RootShell(
      onLogout: () => setState(() => _authed = false),
    );
  }
}

class _WebStartupPlaceholder extends StatelessWidget {
  const _WebStartupPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF05070B),
      child: Center(
        child: SizedBox(
          width: 220,
          child: LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Color(0x22FFFFFF),
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF64E5C4)),
          ),
        ),
      ),
    );
  }
}
