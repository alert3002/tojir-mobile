import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/payment_config.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/support_contact.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppScaffold(
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: dark ? _cardBg : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.2 : 0.35)),
              ),
              child: Column(
                children: [
                  const SupportMessengerIcons(size: 28, gap: 10, active: true),
                  const SizedBox(height: 14),
                  Text(
                    'Техподдержка',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Напишите в Telegram или WhatsApp — ответим по вопросам Tojir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: _blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => Clipboard.setData(
                        const ClipboardData(text: PaymentConfig.supportPhone),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_in_talk_rounded, color: _blue, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              PaymentConfig.supportPhone,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Нажмите, чтобы скопировать номер',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  const SupportMessengerButtons(),
                  const SizedBox(height: 10),
                  _SupportMethod(
                    icon: Icons.phone_outlined,
                    title: 'Позвонить',
                    subtitle: '+${PaymentConfig.supportPhoneIntl}',
                    onTap: SupportContact.callPhone,
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
      color: Colors.black.withValues(alpha: 0.06),
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
