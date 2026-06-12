import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/app_scaffold.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _open(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppScaffold(
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.support_agent_rounded, size: 30, color: _blue),
                  ),
                  const SizedBox(height: 14),
                  Text('Служба поддержки', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    'Мы на связи 24/7, чтобы помочь вам с управлением вашим бизнесом.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  _SupportMethod(
                    icon: Icons.send_rounded,
                    title: 'Написать в Telegram',
                    subtitle: '@tojir_support',
                    onTap: () => _open(Uri.parse('https://t.me/tojir_support')),
                  ),
                  const SizedBox(height: 10),
                  _SupportMethod(
                    icon: Icons.phone_outlined,
                    title: '+992 (00) 000-00-00',
                    subtitle: 'Звонок',
                    onTap: () => _open(Uri.parse('tel:+992000000000')),
                  ),
                  const SizedBox(height: 10),
                  _SupportMethod(
                    icon: Icons.mail_outline_rounded,
                    title: 'support@tojir.tj',
                    subtitle: 'Почта',
                    onTap: () => _open(Uri.parse('mailto:support@tojir.tj')),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_outlined, size: 18, color: Colors.amber.shade300),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Мы не просим пароль. Не сообщайте коды подтверждения третьим лицам.',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    style: FilledButton.styleFrom(backgroundColor: _blue, minimumSize: const Size(double.infinity, 44)),
                    child: const Text('На главную'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pushNamed('/privacy'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                    child: const Text('Политика'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => _open(Uri.parse('mailto:support@tojir.tj')),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                    child: const Text('Написать письмо'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportMethod extends StatelessWidget {
  const _SupportMethod({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: _blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
