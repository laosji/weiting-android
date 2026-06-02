import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _privacyUrl = 'https://fm.showmyapps.cc/privacy';
  static const _termsUrl = 'https://fm.showmyapps.cc/terms';
  static const _feedbackEmail = 'support@showmyapps.cc';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfffbfaf7),
      appBar: AppBar(
        title: const Text('关于微听'),
        backgroundColor: const Color(0xfffbfaf7),
        elevation: 0,
        foregroundColor: const Color(0xff242520),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  final version = info == null
                      ? '...'
                      : '${info.version} (${info.buildNumber})';
                  return _Section(
                    title: '版本信息',
                    children: [
                      _kv('版本号', version),
                      _kv('应用名', info?.appName ?? '微听'),
                      _kv('包名', info?.packageName ?? '-'),
                    ],
                  );
                },
              ),
              _Section(
                title: '内容来源声明',
                children: const [
                  Text(
                    '微听本身不存储任何音频内容。所有节目均来自用户公开分享的第三方平台'
                    '（微博、小红书等）链接，App 仅在用户主动粘贴时为该链接'
                    '提取可播放的音频流，作为浏览器播放的便利工具。\n\n'
                    '若您是相关内容的版权方，希望我们屏蔽某个来源，请通过下方'
                    '邮箱与我们联系，我们会在 3 个工作日内处理。',
                    style: TextStyle(height: 1.55, color: Color(0xff5e5b54)),
                  ),
                ],
              ),
              _Section(
                title: '协议与隐私',
                children: [
                  _LinkRow(
                    label: '用户协议',
                    onTap: () => _open(context, _termsUrl),
                  ),
                  _LinkRow(
                    label: '隐私政策',
                    onTap: () => _open(context, _privacyUrl),
                  ),
                  _LinkRow(
                    label: '联系与版权投诉：$_feedbackEmail',
                    onTap: () => _open(context, 'mailto:$_feedbackEmail'),
                  ),
                ],
              ),
              _Section(
                title: '开源致谢',
                children: const [
                  Text(
                    '本应用使用了 just_audio / just_audio_background / shared_preferences '
                    '/ http / url_launcher / package_info_plus / connectivity_plus 等开源组件，'
                    '在此一并致谢。',
                    style: TextStyle(height: 1.55, color: Color(0xff5e5b54)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打不开链接：$url')),
      );
    }
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                key,
                style: const TextStyle(
                  color: Color(0xffaaa49a),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: Color(0xff242520),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xfffffefa),
        border: Border.all(color: const Color(0xffeee8df)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xff242520),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xff242520),
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Color(0xffaaa49a),
            ),
          ],
        ),
      ),
    );
  }
}
