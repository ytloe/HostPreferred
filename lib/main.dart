import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
// import 'package:flutter/material.dart' as material;
import 'package:system_theme/system_theme.dart';
import 'package:url_launcher/url_launcher.dart';

// Import the SVG package if you choose to use SVG icons
// import 'package:flutter_svg/flutter_svg.dart';

import 'src/rust/api/io.dart';
import 'src/rust/api/models.dart';
import 'src/rust/api/optimizer.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final accentColor = SystemTheme.accentColor.accent;
    return FluentApp(
      title: 'HostPreferred',
      themeMode: ThemeMode.system,
      theme: FluentThemeData(
        brightness: Brightness.light,
        accentColor: accentColor.toAccentColor(),
        fontFamily: 'Microsoft YaHei',
      ),
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: accentColor.toAccentColor(),
        fontFamily: 'Microsoft YaHei',
      ),
      debugShowCheckedModeBanner: false,
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  String _infoBarMessage = '';
  bool _isInfoBarVisible = false;
  Timer? _infoBarTimer;
  String? _hostsDirPath;

  @override
  void initState() {
    super.initState();
    try {
      _hostsDirPath = getHostsDir();
    } catch (e) {
      _hostsDirPath = '路径获取失败';
      _showInfoBar('获取 hosts 目录失败: $e');
    }
  }

  @override
  void dispose() {
    _infoBarTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveCurrentHost() async {
    try {
      final backupPath = await saveCurrentHosts();
      _showInfoBar('备份成功！已保存至: $backupPath');
    } catch (e) {
      _showInfoBar('备份失败: $e');
    }
  }

  Future<void> _optimizeGitHubHost() async {
    _showInfoBar('正在优选并应用 GitHub Host...');
    try {
      final successMessage = await optimizeHosts(
        target: OptimizationTarget.gitHub,
      );
      _showInfoBar(successMessage);
    } catch (e) {
      _showInfoBar('操作失败: $e');
    }
  }

  Future<void> _optimizeCloudflareHost() async {
    _showInfoBar('正在优选并应用 Cloudflare Host...');
    try {
      final successMessage = await optimizeHosts(
        target: OptimizationTarget.cloudflare,
      );
      _showInfoBar(successMessage);
    } catch (e) {
      _showInfoBar('操作失败: $e');
    }
  }

  Future<void> _optimizeNexusModsHost() async {
    _showInfoBar('正在优选并应用 Nexus Mods Host...');
    try {
      final successMessage = await optimizeHosts(
        target: OptimizationTarget.nexusMods,
      );
      _showInfoBar(successMessage);
    } catch (e) {
      _showInfoBar('操作失败: $e');
    }
  }

  Future<void> _revertHost() async {
    _showInfoBar('正在从备份还原 Host...');
    try {
      final successMessage = await revertHosts();
      _showInfoBar(successMessage);
    } catch (e) {
      _showInfoBar('还原失败: $e');
    }
  }

  void _showInfoBar(String message) {
    _infoBarTimer?.cancel();
    setState(() {
      _infoBarMessage = message;
      _isInfoBarVisible = true;
    });
    _infoBarTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) {
        setState(() => _isInfoBarVisible = false);
      }
    });
  }

  Future<void> _openHostsDir() async {
    if (_hostsDirPath != null && _hostsDirPath != '路径获取失败') {
      final uri = Uri.directory(_hostsDirPath!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showInfoBar('无法打开目录: $_hostsDirPath');
      }
    } else {
      _showInfoBar('Hosts 目录路径无效，无法打开。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = FluentTheme.of(context).brightness;
    final Color iconColor = brightness == Brightness.dark
        ? Colors.white.withOpacity(0.9)
        : Colors.black.withOpacity(0.8);

    return Stack(
      children: [
        ScaffoldPage(
          header: const PageHeader(
            title: Row(
              children: [
                Spacer(),
                Text(
                  'HostPreferred',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                Spacer(),
              ],
            ),
          ),
          content: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildActionButton(
                  assetPath: 'assets/icons/save.png',
                  label: '保存当前 Host',
                  onPressed: _saveCurrentHost,
                  iconColor: iconColor,
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  assetPath: 'assets/icons/github.png',
                  label: 'GitHub 优选',
                  onPressed: _optimizeGitHubHost,
                  iconColor: brightness == Brightness.dark
                      ? Colors.white
                      : null,
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  assetPath: 'assets/icons/cloudflare.png',
                  label: 'Cloudflare 优选',
                  onPressed: _optimizeCloudflareHost,
                  iconColor: null,
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  assetPath: 'assets/icons/nexusmods.png',
                  label: 'Nexus Mods 优选',
                  onPressed: _optimizeNexusModsHost,
                  iconColor: null,
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  assetPath: 'assets/icons/revert.png',
                  label: '还原 Host',
                  onPressed: _revertHost,
                  iconColor: iconColor,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.5),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _isInfoBarVisible
                  ? InfoBar(
                      key: ValueKey<String>(_infoBarMessage),
                      title: Text(_infoBarMessage),
                      severity: InfoBarSeverity.info,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: HyperlinkButton(
              onPressed: _openHostsDir,
              child: const Text('备份路径'),
            ),
          ),
        ),
      ],
    );
  }

  // ## 这里是主要修改点：按钮颜色 ##
  Widget _buildActionButton({
    required String assetPath,
    required String label,
    required VoidCallback onPressed,
    Color? iconColor,
  }) {
    final brightness = FluentTheme.of(context).brightness;
    // 为按钮选择一个柔和的、能适应主题的灰色
    final Color buttonColor = brightness == Brightness.dark
        ? Colors.grey[120] // 深色模式下的按钮颜色
        : Colors.grey[60]; // 浅色模式下的按钮颜色

    return FilledButton(
      onPressed: onPressed,
      style: ButtonStyle(
        // 应用我们自定义的颜色
        backgroundColor: WidgetStateProperty.all(buttonColor),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 12.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            assetPath,
            width: 32,
            height: 32,
            color: iconColor,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
