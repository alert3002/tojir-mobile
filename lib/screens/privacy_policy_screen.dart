import 'package:flutter/material.dart';

import '../widgets/app_scaffold.dart';

const _cardBg = Color(0xFF151D2E);
const _blue = Color(0xFF2563EB);

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppScaffold(
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('Политика конфиденциальности', _blue),
                _pill('Последнее обновление: 17 апреля 2026 г.', const Color(0xFF6366F1)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Как Tojir.tj собирает и защищает данные',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface, height: 1.25),
            ),
            const SizedBox(height: 8),
            Text(
              'Мы бережно относимся к информации пользователей и используем её только для работы сервиса, безопасности и улучшения качества.',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                  child: const Text('На главную'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/support'),
                  child: const Text('Техподдержка'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _LegalCard(
              icon: Icons.verified_user_outlined,
              title: '1. Общие положения',
              body:
                  'Настоящая политика конфиденциальности описывает, как Tojir.tj собирает, использует и защищает информацию, которую вы предоставляете при использовании нашего сервиса.',
            ),
            const SizedBox(height: 10),
            _LegalCard(
              icon: Icons.storage_outlined,
              title: '2. Какие данные мы собираем',
              bullets: const [
                'Данные профиля (номер телефона, имя, название магазина).',
                'Данные о транзакциях и складских запасах для обеспечения работы сервиса.',
                'Технические данные (IP-адрес, тип устройства).',
              ],
            ),
            const SizedBox(height: 10),
            _LegalCard(
              icon: Icons.public_outlined,
              title: '3. Использование данных',
              body:
                  'Мы используем собранные данные для предоставления услуг, обработки ваших операций и информирования о важных обновлениях системы безопасности.',
            ),
            const SizedBox(height: 10),
            _LegalCard(
              icon: Icons.lock_outline_rounded,
              title: '4. Защита информации',
              body:
                  'Мы используем современные методы шифрования (SSL) для защиты ваших данных от несанкционированного доступа.\n\nЕсли у вас есть вопросы по обработке данных, свяжитесь с нами через страницу поддержки.',
            ),
          ],
        ),
      ),
    );
  }
}

Widget _pill(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
  );
}

class _LegalCard extends StatelessWidget {
  const _LegalCard({required this.icon, required this.title, this.body, this.bullets});
  final IconData icon;
  final String title;
  final String? body;
  final List<String>? bullets;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _blue),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 10),
          if (body != null) Text(body!, style: TextStyle(color: cs.onSurfaceVariant, height: 1.45)),
          if (bullets != null)
            ...bullets!.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: cs.onSurfaceVariant)),
                    Expanded(child: Text(b, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
