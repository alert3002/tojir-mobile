import 'package:flutter/material.dart';

import '../utils/home_cards.dart';

/// Сетка 3×5 главной бизнесмена — зеркало web `.tojir-mobile-grid-card--accent`.
class BusinessmanHomeGrid extends StatelessWidget {
  const BusinessmanHomeGrid({
    super.key,
    required this.cards,
    required this.debtWe,
    required this.debtCo,
    required this.onTap,
  });

  final List<HomeCard> cards;
  final String? debtWe;
  final String? debtCo;
  final ValueChanged<String> onTap;

  static const _cardBgDark = Color(0xFF151D2E);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? _cardBgDark : Colors.white;
    final textColor = dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.88,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        final accent = card.color;
        final isDebts = card.route == '/debts' && card.label == 'Долги';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(card.route),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(5, 10, 5, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Color.alphaBlend(accent.withValues(alpha: 0.3), Colors.transparent)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(accent.withValues(alpha: 0.14), cardBg),
                    cardBg,
                  ],
                  stops: const [0.0, 0.72],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.2 : 0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (isDebts && (debtWe != null || debtCo != null))
                          Positioned(
                            top: 3,
                            left: 4,
                            right: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (debtWe != null)
                                  _DebtFigure(text: debtWe!, color: const Color(0xFFE11D48)),
                                if (debtCo != null)
                                  _DebtFigure(text: debtCo!, color: const Color(0xFF059669)),
                              ],
                            ),
                          ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              color: accent.withValues(alpha: 0.14),
                              border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.18),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(card.icon, size: 20, color: accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DebtFigure extends StatelessWidget {
  const _DebtFigure({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 8.8,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.4,
        color: color,
        shadows: const [
          Shadow(color: Color(0xF2FFFFFF), blurRadius: 5),
          Shadow(color: Color(0x8C0F172A), offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
    );
  }
}
