import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Обёртка shimmer с цветами под светлую/тёмную тему (как в маркетплейс-приложениях).
class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0);
    final hi = dark ? const Color(0xFF475569) : const Color(0xFFF8FAFC);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: hi,
      period: const Duration(milliseconds: 1300),
      child: child,
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.height, this.width, this.radius = 12});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Полноэкранный скелетон: «поиск», чипы, сетка карточек (как на референсе).
class SkeletonFeedPage extends StatelessWidget {
  const SkeletonFeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _Bone(height: 44, width: 44, radius: 12),
                  const SizedBox(width: 10),
                  const Expanded(child: _Bone(height: 44, radius: 14)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: List.generate(
                  6,
                  (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < 5 ? 8 : 0),
                      child: const _Bone(height: 36, radius: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: 6,
                  itemBuilder: (_, i) => Column(
                    key: ValueKey(i),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: _Bone(height: double.infinity, radius: 14)),
                      const SizedBox(height: 10),
                      const _Bone(height: 12, radius: 6),
                      const SizedBox(height: 6),
                      const _Bone(height: 12, width: 120, radius: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Скелетон списка (строки) для таблиц/списков ERP.
class SkeletonListBlock extends StatelessWidget {
  const SkeletonListBlock({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: List.generate(
            rows,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Bone(height: 48, width: 48, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: _Bone(height: 14, width: (i % 3 == 0) ? null : 200, radius: 7),
                        ),
                        const SizedBox(height: 8),
                        const _Bone(height: 12, radius: 6),
                        const SizedBox(height: 6),
                        const _Bone(height: 12, width: 160, radius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Компактный блок для вложенных областей (профиль, уведомления).
class SkeletonCardList extends StatelessWidget {
  const SkeletonCardList({super.key, this.cards = 4});

  final int cards;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(
            cards,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Bone(height: 18, width: 200, radius: 8),
                  const SizedBox(height: 10),
                  const _Bone(height: 56, radius: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
