import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/payment_config.dart';
import '../theme/app_shape.dart';

/// iOS: текст инструкции вместо кнопки «Пополнить баланс».
class IosBalanceTopupInstructions extends StatelessWidget {
  const IosBalanceTopupInstructions({super.key});

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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        color: cs.primaryContainer.withValues(alpha: 0.28),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Пополнение баланса',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Переведите нужную сумму на номер ${PaymentConfig.supportPhone} '
            'через одно из приложений ниже. Затем отправьте чек об оплате '
            'в Telegram или WhatsApp на этот же номер — ${PaymentConfig.supportPhone}. '
            'После проверки баланс пополнится автоматически.',
            style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurface.withValues(alpha: 0.92)),
          ),
          const SizedBox(height: 12),
          const _BankIconsRow(),
          const SizedBox(height: 12),
          _MessengerRow(
            onTelegram: () => _openUrl(PaymentConfig.telegramUrl),
            onWhatsApp: () => _openUrl(PaymentConfig.whatsappUrl),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _copyPhone(context),
            borderRadius: AppShape.br,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: AppShape.br,
                color: cs.surface.withValues(alpha: 0.65),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone_android, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Номер: ${PaymentConfig.supportPhone}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                  ),
                  Icon(Icons.copy, size: 18, color: cs.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BankIconsRow extends StatelessWidget {
  const _BankIconsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _BankTile(asset: 'assets/payments/alif.png', label: 'Alif Mobi')),
        SizedBox(width: 8),
        Expanded(child: _BankTile(asset: 'assets/payments/eskhata.png', label: 'Эсхата')),
        SizedBox(width: 8),
        Expanded(child: _BankTile(asset: 'assets/payments/dc.png', label: 'Dushanbe City', wide: true)),
      ],
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({
    required this.asset,
    required this.label,
    this.wide = false,
  });

  final String asset;
  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: wide ? 1.45 : 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: wide ? Colors.white : null,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                asset,
                fit: wide ? BoxFit.contain : BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, height: 1.15),
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
          child: _MessengerChip(
            asset: 'assets/payments/telegram.svg',
            label: 'Telegram',
            color: const Color(0xFF26A5E4),
            onTap: onTelegram,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MessengerChip(
            asset: 'assets/payments/whatsapp.svg',
            label: 'WhatsApp',
            color: const Color(0xFF25D366),
            onTap: onWhatsApp,
          ),
        ),
      ],
    );
  }
}

class _MessengerChip extends StatelessWidget {
  const _MessengerChip({
    required this.asset,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String asset;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                asset,
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
