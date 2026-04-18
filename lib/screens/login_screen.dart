import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_controller.dart';
import '../config/app_config.dart';
import '../theme/app_shape.dart';
import '../theme/theme_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _offerAcceptKey = 'tojir_offer_accepted_v1';

  final _phone = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _otp = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  bool _offerAccepted = false;
  int _resendLeft = 0;
  String _step = 'phone';
  bool _otpAutoSubmitScheduled = false;

  @override
  void dispose() {
    _phone.dispose();
    for (final c in _otp) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadOfferAccepted();
    _phone.addListener(_onPhoneChanged);
    for (var i = 0; i < 6; i++) {
      _otpFocus[i].addListener(() => setState(() {}));
    }
  }

  Future<void> _loadOfferAccepted() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_offerAcceptKey) == '1';
    if (mounted) setState(() => _offerAccepted = v);
  }

  Future<void> _setOfferAccepted(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_offerAcceptKey, v ? '1' : '0');
    if (mounted) setState(() => _offerAccepted = v);
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String _formatTJPhone9(String digits9) {
    final d = _digitsOnly(digits9);
    final a = d.length >= 2 ? d.substring(0, 2) : d;
    final b = d.length >= 5 ? d.substring(2, 5) : (d.length > 2 ? d.substring(2) : '');
    final c = d.length >= 7 ? d.substring(5, 7) : (d.length > 5 ? d.substring(5) : '');
    final e = d.length >= 9 ? d.substring(7, 9) : (d.length > 7 ? d.substring(7) : '');
    return [a, b, c, e].where((x) => x.isNotEmpty).join(' ');
  }

  void _onPhoneChanged() {
    final digits = _digitsOnly(_phone.text).substring(0, (_digitsOnly(_phone.text).length).clamp(0, 9));
    final formatted = _formatTJPhone9(digits);
    if (_phone.text != formatted) {
      _phone.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  bool get _phoneIsComplete => _digitsOnly(_phone.text).length == 9;

  String get _otpCode => _otp.map((c) => c.text).join();

  void _clearOtp() {
    for (final c in _otp) {
      c.clear();
    }
  }

  void _focusFirstOtp() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _otpFocus[0].requestFocus();
    });
  }

  void _handleOtpChanged(int i, String raw) {
    var only = raw.replaceAll(RegExp(r'\D'), '');
    if (only.length > 1) {
      only = only.substring(0, 6);
      for (var k = 0; k < 6; k++) {
        _otp[k].text = k < only.length ? only[k] : '';
      }
      if (only.length >= 6) {
        _otpFocus[5].requestFocus();
      } else {
        _otpFocus[only.length.clamp(0, 5)].requestFocus();
      }
      setState(() {});
      _tryAutoSubmitOtp();
      return;
    }
    if (_otp[i].text != only) {
      _otp[i].text = only;
      _otp[i].selection = TextSelection.collapsed(offset: only.length);
    }
    if (only.isNotEmpty && i < 5) {
      _otpFocus[i + 1].requestFocus();
    }
    setState(() {});
    _tryAutoSubmitOtp();
  }

  void _tryAutoSubmitOtp() {
    if (_otpCode.length != 6 || _loading || !_offerAccepted || _otpAutoSubmitScheduled) return;
    _otpAutoSubmitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _otpAutoSubmitScheduled = false;
      if (mounted) _confirmCode();
    });
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _ensureOfferAccepted() {
    if (_offerAccepted) return true;
    _showSnack('Поставьте галочку: вы принимаете условия оферты');
    return false;
  }

  Future<void> _requestCode() async {
    if (!_ensureOfferAccepted()) return;
    if (!_phoneIsComplete) {
      _showSnack('Введите 9 цифр после +992');
      return;
    }
    if (_resendLeft > 0) return;
    setState(() => _loading = true);
    try {
      await context.read<SessionController>().requestSmsCode(_digitsOnly(_phone.text));
      if (!mounted) return;
      setState(() {
        _step = 'code';
        _resendLeft = 60;
        _clearOtp();
      });
      _tickResend();
      _focusFirstOtp();
      _showSnack('Код отправлен');
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tickResend() async {
    while (mounted && _resendLeft > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _resendLeft = _resendLeft > 0 ? _resendLeft - 1 : 0);
    }
  }

  Future<void> _confirmCode() async {
    if (!_ensureOfferAccepted()) return;
    if (!_phoneIsComplete) {
      _showSnack('Введите телефон');
      return;
    }
    final code = _otpCode.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      _showSnack('Введите 6 цифр кода');
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<SessionController>().loginWithSms(
            digits9: _digitsOnly(_phone.text),
            code: code,
          );
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openOfferModal() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Договор (публичная оферта) и условия использования'),
        content: const SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Это договор между платформой Tojir и владельцем бизнеса/пользователем сервиса.'),
                SizedBox(height: 12),
                Divider(),
                SizedBox(height: 8),
                Text('Кратко:', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text(
                  '— Сервис предназначен для учёта продаж, остатков и движения товара.\n'
                  '— Вы несёте ответственность за корректность вводимых данных.\n'
                  '— Доступ предоставляется по номеру телефона и коду из SMS.\n'
                  '— Персональные данные обрабатываются для работы сервиса и поддержки пользователей.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOfferFull() async {
    final uri = Uri.parse(AppConfig.offerUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildPhoneHelp(ColorScheme cs) {
    final d = _digitsOnly(_phone.text);
    if (d.isEmpty) return const SizedBox(height: 22);
    if (_phoneIsComplete) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Номер корректный',
          style: TextStyle(
            fontSize: 14,
            color: const Color(0xFF52C41A).withValues(alpha: cs.brightness == Brightness.dark ? 0.95 : 1),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Введите ещё ${9 - d.length} цифр',
        style: TextStyle(fontSize: 14, color: cs.error),
      ),
    );
  }

  Widget _buildOtpBoxes(ColorScheme cs) {
    final primary = cs.primary;
    final inactive = cs.outlineVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        final boxW = isNarrow ? 40.0 : 44.0;
        final boxH = isNarrow ? 50.0 : 54.0;
        final gap = isNarrow ? 6.0 : 8.0;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: 10,
          children: List.generate(6, (i) {
            return SizedBox(
              width: boxW,
              height: boxH,
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.backspace &&
                      _otp[i].text.isEmpty &&
                      i > 0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _otpFocus[i - 1].requestFocus();
                      if (_otp[i - 1].text.isNotEmpty) {
                        _otp[i - 1].clear();
                        setState(() {});
                      }
                    });
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _otp[i],
                  focusNode: _otpFocus[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.1,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: cs.surface.withValues(alpha: cs.brightness == Brightness.dark ? 0.55 : 0.85),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: AppShape.br,
                      borderSide: BorderSide(color: inactive, width: 1.2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppShape.br,
                      borderSide: BorderSide(color: inactive, width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppShape.br,
                      borderSide: BorderSide(color: primary, width: 2),
                    ),
                  ),
                  onChanged: (s) => _handleOtpChanged(i, s),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildOfferRow(ColorScheme cs) {
    final baseStyle = TextStyle(fontSize: 15, color: cs.onSurface, height: 1.35);
    final linkStyle = TextStyle(fontSize: 15, color: cs.primary, fontWeight: FontWeight.w600);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _offerAccepted,
          onChanged: (v) => _setOfferAccepted(v ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: baseStyle,
              children: [
                const TextSpan(text: 'Я принимаю условия '),
                TextSpan(
                  text: 'оферты',
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()..onTap = _openOfferModal,
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: '(полная версия)',
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()..onTap = _openOfferFull,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlowButton({
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    final enabled = onPressed != null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: AppShape.br),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset(
                      'assets/images/tojir_logo.png',
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: AppShape.br,
                            ),
                            child: Icon(Icons.storefront, size: 16, color: cs.onPrimary),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Tojir',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              letterSpacing: 0.2,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: AppShape.br,
                      onTap: () => context.read<ThemeController>().toggle(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: AppShape.br,
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.10),
                          ),
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                        ),
                        child: Icon(isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final isSmall = constraints.maxWidth < 640;
                  return Align(
                    alignment: isSmall ? Alignment.topCenter : Alignment.center,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(24, isSmall ? 48 : 24, 24, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Быстро и удобно — начните за минуту',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  color: cs.onSurface,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: AppShape.brLg,
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.55),
                                  ),
                                  color: isDark ? cs.surfaceContainerHigh.withValues(alpha: 0.95) : cs.surface,
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.primary.withValues(alpha: isDark ? 0.12 : 0.07),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Вход',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 19,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.55)),
                                      const SizedBox(height: 18),
                                      if (_step == 'phone') ...[
                                        Text.rich(
                                          TextSpan(
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                              color: cs.onSurface,
                                            ),
                                            children: const [
                                              TextSpan(text: '* ', style: TextStyle(color: Color(0xFFFF4D4F))),
                                              TextSpan(text: 'Телефон'),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          decoration: BoxDecoration(
                                            borderRadius: AppShape.br,
                                            border: Border.all(color: cs.outlineVariant),
                                            color: cs.surface.withValues(alpha: isDark ? 0.45 : 0.6),
                                          ),
                                          child: Row(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                                                child: Text(
                                                  '+992',
                                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface),
                                                ),
                                              ),
                                              Container(width: 1, height: 28, color: cs.outlineVariant),
                                              Expanded(
                                                child: TextField(
                                                  controller: _phone,
                                                  keyboardType: TextInputType.phone,
                                                  style: TextStyle(fontSize: 17, color: cs.onSurface, fontWeight: FontWeight.w500),
                                                  decoration: InputDecoration(
                                                    prefixIcon: Icon(Icons.phone_android_outlined, color: cs.onSurfaceVariant, size: 22),
                                                    hintText: '90 123 45 67',
                                                    hintStyle: TextStyle(fontSize: 17, color: cs.onSurfaceVariant),
                                                    border: InputBorder.none,
                                                    isDense: true,
                                                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _buildPhoneHelp(cs),
                                      ],
                                      if (_step == 'code') ...[
                                        Text(
                                          'Код из SMS',
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onSurface),
                                        ),
                                        const SizedBox(height: 14),
                                        _buildOtpBoxes(cs),
                                        const SizedBox(height: 8),
                                      ],
                                      const SizedBox(height: 16),
                                      _buildOfferRow(cs),
                                      const SizedBox(height: 18),
                                      _buildGlowButton(
                                        onPressed: (_loading || !_offerAccepted)
                                            ? null
                                            : (_step == 'phone' ? _requestCode : _confirmCode),
                                        child: _loading
                                            ? const SizedBox(
                                                height: 22,
                                                width: 22,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : Text(
                                                _step == 'phone' ? 'Получить код' : 'Войти',
                                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                                              ),
                                      ),
                                      if (_step == 'code') ...[
                                        const SizedBox(height: 14),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: _resendLeft > 0
                                              ? Text(
                                                  'Отправить ещё код ($_resendLeftс)',
                                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                                                )
                                              : TextButton(
                                                  onPressed: _loading ? null : _requestCode,
                                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                                  child: Text('Отправить ещё код', style: TextStyle(fontSize: 15, color: cs.primary)),
                                                ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 48,
                                          child: OutlinedButton(
                                            onPressed: () {
                                              setState(() {
                                                _step = 'phone';
                                                _clearOtp();
                                              });
                                            },
                                            style: OutlinedButton.styleFrom(
                                              shape: RoundedRectangleBorder(borderRadius: AppShape.br),
                                              side: BorderSide(color: cs.outlineVariant),
                                            ),
                                            child: Text('Сменить номер', style: TextStyle(fontSize: 16, color: cs.onSurface)),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
