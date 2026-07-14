import 'package:flutter/material.dart';

import '../utils/home_cards.dart';

/// Сетка 3 колонки — квадратные кнопки; иконки по центру.
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
  static const _textDark = Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = dark ? _cardBgDark : Colors.white;
    final textColor = dark ? _textDark : const Color(0xFF0F172A);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        final accent = card.color;
        final isDebts = card.route == '/debts';
        final showDebt = isDebts && (debtWe != null || debtCo != null);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(card.route),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.30)),
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
                    color: Colors.black.withValues(alpha: dark ? 0.20 : 0.04),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (showDebt)
                    Positioned(
                      top: 4,
                      left: 4,
                      right: 4,
                      child: Column(
                        children: [
                          if (debtWe != null) _DebtPill(text: debtWe!, minus: true),
                          if (debtCo != null) ...[
                            if (debtWe != null) const SizedBox(height: 2),
                            _DebtPill(text: debtCo!, minus: false),
                          ],
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(6, showDebt ? 26 : 8, 6, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              color: accent.withValues(alpha: 0.14),
                              border: Border.all(color: accent.withValues(alpha: 0.40), width: 1.5),
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
                          const SizedBox(height: 6),
                          Text(
                            card.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
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

class _DebtPill extends StatelessWidget {
  const _DebtPill({required this.text, required this.minus});
  final String text;
  final bool minus;

  @override
  Widget build(BuildContext context) {
    final color = minus ? const Color(0xFFFB7185) : const Color(0xFF34D399);
    final bg = minus ? const Color(0x2EE11D48) : const Color(0x2E059669);
    final border = minus ? const Color(0x59FB7185) : const Color(0x5934D399);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 96),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, height: 1.2, color: color),
        ),
      ),
    );
  }
}
