import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/payment_config.dart';

/// Telegram / WhatsApp / телефон техподдержки Tojir.
abstract final class SupportContact {
  static Future<void> openTelegram() => _open(Uri.parse(PaymentConfig.telegramUrl));

  static Future<void> openWhatsApp() => _open(Uri.parse(PaymentConfig.whatsappUrl));

  static Future<void> callPhone() => _open(Uri.parse('tel:+${PaymentConfig.supportPhoneIntl}'));

  static Future<void> _open(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Две иконки мессенджеров (нижнее меню, карточки).
class SupportMessengerIcons extends StatelessWidget {
  const SupportMessengerIcons({
    super.key,
    this.size = 16,
    this.gap = 5,
    this.active = false,
    this.dark = false,
  });

  final double size;
  final double gap;
  final bool active;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final inactive = dark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final tg = active ? const Color(0xFF26A5E4) : inactive;
    final wa = active ? const Color(0xFF25D366) : inactive;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/payments/telegram.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(tg, BlendMode.srcIn),
        ),
        SizedBox(width: gap),
        SvgPicture.asset(
          'assets/payments/whatsapp.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(wa, BlendMode.srcIn),
        ),
      ],
    );
  }
}

/// Кнопки Telegram + WhatsApp (экран поддержки).
class SupportMessengerButtons extends StatelessWidget {
  const SupportMessengerButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MessengerChip(
            asset: 'assets/payments/telegram.svg',
            label: 'Telegram',
            color: const Color(0xFF26A5E4),
            onTap: SupportContact.openTelegram,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MessengerChip(
            asset: 'assets/payments/whatsapp.svg',
            label: 'WhatsApp',
            color: const Color(0xFF25D366),
            onTap: SupportContact.openWhatsApp,
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
