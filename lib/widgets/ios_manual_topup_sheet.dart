import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/payment_config.dart';
import '../theme/app_shape.dart';

/// iOS: инструкция по ручному пополнению (банки + чек в Telegram/WhatsApp).
class IosManualTopupSheet extends StatelessWidget {
  const IosManualTopupSheet({
    super.key,
    required this.amountController,
    required this.currentBalance,
    required this.onClose,
  });

  final TextEditingController amountController;
  final double currentBalance;
  final VoidCallback onClose;

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyPhone(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: PaymentConfig.supportPhone));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Номер скопирован')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
    final amountLabel = amount != null && amount > 0 ? '${amount.toStringAsFixed(2)} TJS' : 'нужную сумму';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.br,
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Пополнить баланс',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: cs.onSurface),
                  ),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close), tooltip: 'Закрыть'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Текущий баланс: ${currentBalance.toStringAsFixed(2)} TJS',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Сумма пополнения (TJS)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: AppShape.br,
                color: cs.primaryContainer.withValues(alpha: 0.35),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Инструкция',
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),
                  _step(1, 'Оплатите $amountLabel на номер ${PaymentConfig.supportPhone} через одно из приложений:'),
                  const SizedBox(height: 12),
                  _BankIconsRow(),
                  const SizedBox(height: 14),
                  _step(2, 'Отправьте чек об оплате на этот же номер в Telegram или WhatsApp:'),
                  const SizedBox(height: 12),
                  _MessengerRow(onTelegram: () => _openUrl(PaymentConfig.telegramUrl), onWhatsApp: () => _openUrl(PaymentConfig.whatsappUrl)),
                  const SizedBox(height: 14),
                  _step(3, 'После проверки чека баланс пополнится автоматически (обычно в течение нескольких минут).'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _copyPhone(context),
              borderRadius: AppShape.br,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: AppShape.br,
                  border: Border.all(color: cs.outline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_android, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Номер для оплаты', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          Text(
                            PaymentConfig.supportPhone,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.copy, size: 20, color: cs.primary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openUrl(PaymentConfig.telegramUrl),
                    icon: SvgPicture.asset('assets/payments/telegram.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(Color(0xFF26A5E4), BlendMode.srcIn)),
                    label: const Text('Telegram'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openUrl(PaymentConfig.whatsappUrl),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    icon: SvgPicture.asset('assets/payments/whatsapp.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Служба поддержки: ${PaymentConfig.supportPhone}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(int n, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4, fontSize: 14))),
      ],
    );
  }
}

class _BankIconsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _BankTile(asset: 'assets/payments/alif.svg', label: 'Alif Mobi')),
        const SizedBox(width: 8),
        Expanded(child: _BankTile(asset: 'assets/payments/eskhata.svg', label: 'Эсхата')),
        const SizedBox(width: 8),
        Expanded(child: _BankTile(asset: 'assets/payments/dc.svg', label: 'Dushanbe City')),
      ],
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({required this.asset, required this.label});

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SvgPicture.asset(asset, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, height: 1.2),
        ),
      ],
    );
  }
}

class _MessengerRow extends StatelessWidget {
  const _MessengerRow({required this.onTelegram, required this.onWhatsApp});

  final VoidCallback onTelegram;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MessengerTile(
            asset: 'assets/payments/telegram.svg',
            label: 'Telegram',
            bg: const Color(0xFF26A5E4),
            onTap: onTelegram,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MessengerTile(
            asset: 'assets/payments/whatsapp.svg',
            label: 'WhatsApp',
            bg: const Color(0xFF25D366),
            onTap: onWhatsApp,
          ),
        ),
      ],
    );
  }
}

class _MessengerTile extends StatelessWidget {
  const _MessengerTile({
    required this.asset,
    required this.label,
    required this.bg,
    required this.onTap,
  });

  final String asset;
  final String label;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(asset, width: 28, height: 28, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
