import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:system_theme/system_theme.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// 备份当前 Host 文件
  Future<void> _saveCurrentHost() async {
    try {
      final backupPath = await saveCurrentHosts();
      _showInfoBar('备份成功！已保存至: $backupPath');
    } catch (e) {
      _showInfoBar('备份失败: $e');
    }
  }

  /// 优选 GitHub Host
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

  /// 优选 Cloudflare Host
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

  /// 【新功能】从备份还原 Host
  Future<void> _revertHost() async {
    _showInfoBar('正在从备份还原 Host...');
    try {
      final successMessage = await revertHosts();
      _showInfoBar(successMessage);
    } catch (e) {
      _showInfoBar('还原失败: $e');
    }
  }

  /// 显示一个信息提示条，3秒后自动消失
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

  /// 打开 Host 文件所在目录
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
                  icon: material.Icons.save_alt,
                  label: '保存当前 Host',
                  onPressed: _saveCurrentHost,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _optimizeGitHubHost,
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 12.0),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(material.Icons.hub_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('GitHub 优选'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _optimizeCloudflareHost,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(Colors.orange),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 12.0),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(material.Icons.cloud_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Cloudflare 优选'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildActionButton(
                  icon: material.Icons.replay_circle_filled,
                  label: '还原 Host',
                  onPressed: _revertHost,
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Button(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 12.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(label)],
      ),
    );
  }
}
