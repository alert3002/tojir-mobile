import 'package:flutter/material.dart';

import '../theme/auth_theme.dart';

/// Круглый переключатель оферты — как на веб-странице входа (не квадратный Checkbox).
class AuthOfferCircleToggle extends StatelessWidget {
  const AuthOfferCircleToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.dark,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final borderColor = dark ? Colors.white : AuthTheme.textLight.withValues(alpha: 0.5);
    return Semantics(
      checked: value,
      button: true,
      label: 'Принять условия оферты',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? AuthTheme.primary : Colors.transparent,
            border: Border.all(color: value ? AuthTheme.primary : borderColor, width: 2),
          ),
          child: value
              ? const Icon(Icons.check, size: 10, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
