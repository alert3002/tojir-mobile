import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Бренд на странице входа — как web `Logo.jsx` size="small" (logo.png 28px + TOJIr).
class TojirAuthBrandLogo extends StatelessWidget {
  const TojirAuthBrandLogo({super.key});

  static const _iconPath = 'assets/images/tojir_logo_icon.png';

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2563EB);
    const white = Color(0xFFF1F5F9);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            _iconPath,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                ),
              ),
              child: const Icon(Icons.storefront_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.45,
              height: 1,
            ),
            children: const [
              TextSpan(text: 'TOJI', style: TextStyle(color: white)),
              TextSpan(text: 'r', style: TextStyle(color: blue, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Логотип TOJIr — шапка / drawer (иконка + подпись).
class TojirLogo extends StatelessWidget {
  const TojirLogo({super.key, this.height = 32, this.dark = false});

  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final iconSize = height * 0.875;
    final fontSize = height * 0.47;
    final nameColor = dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final rColor = dark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            TojirAuthBrandLogo._iconPath,
            width: iconSize,
            height: iconSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SvgPicture.asset(
              'assets/images/tojir_logo.svg',
              height: iconSize,
              fit: BoxFit.contain,
              colorFilter: dark ? const ColorFilter.mode(Color(0xFFF1F5F9), BlendMode.srcIn) : null,
              placeholderBuilder: (_) => _NameOnly(height: height, color: nameColor, rColor: rColor),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _NameOnly(height: height, color: nameColor, rColor: rColor, fontSize: fontSize),
      ],
    );
  }
}

class _NameOnly extends StatelessWidget {
  const _NameOnly({
    required this.height,
    required this.color,
    required this.rColor,
    this.fontSize,
  });

  final double height;
  final Color color;
  final Color rColor;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final fs = fontSize ?? height * 0.56;
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: color, height: 1),
        children: [
          const TextSpan(text: 'TOJI'),
          TextSpan(text: 'r', style: TextStyle(fontWeight: FontWeight.w700, color: rColor)),
        ],
      ),
    );
  }
}
