import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_controller.dart';
import '../config/app_config.dart';
import '../theme/auth_theme.dart';
import '../utils/tj_phone.dart';
import '../widgets/auth_offer_toggle.dart';
import '../widgets/tojir_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _offerAcceptKey = 'tojir_offer_accepted_v1';

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _referral = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _offerAccepted = false;
  int _resendLeft = 0;
  String _step = 'phone';
  bool _isNewUser = false;
  bool _showReferral = false;
  bool _codeAutoSubmitScheduled = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _referral.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadOfferAccepted();
    _phone.addListener(_onPhoneChanged);
  }

  Future<void> _loadOfferAccepted() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_offerAcceptKey) == '1';
    if (mounted) setState(() => _offerAccepted = v);
  }

  Future<void> _setOfferAccepted(bool v) async {
    final p = await SharedPreferences.getInstance();
    if (v) {
      await p.setString(_offerAcceptKey, '1');
    } else {
      await p.remove(_offerAcceptKey);
    }
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

  /// Как на вебе: `2 2 5 4 3 7` (`.tojir-auth-code-input`, letter-spacing).
  static String _formatSmsCode(String digits) {
    final d = _digitsOnly(digits).substring(0, _digitsOnly(digits).length.clamp(0, 6));
    if (d.isEmpty) return '';
    return d.split('').join(' ');
  }

  String get _codeDigits => _digitsOnly(_code.text);

  void _applyCodeDigits(String digits) {
    final clipped = digits.substring(0, digits.length.clamp(0, 6));
    final formatted = _formatSmsCode(clipped);
    if (_code.text != formatted) {
      _code.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  void _onPhoneChanged() {
    var digits = _digitsOnly(_phone.text);
    if (digits.startsWith('992') && digits.length >= 12) {
      digits = digits.substring(3);
    }
    digits = digits.substring(0, digits.length.clamp(0, 9));
    final formatted = _formatTJPhone9(digits);
    if (_phone.text != formatted) {
      _phone.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  bool get _phoneIsComplete => TjPhone.isValidMobile(_phone.text);

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
      _showSnack('Введите номер телефона');
      return;
    }
    if (_resendLeft > 0 && _step == 'code') return;
    setState(() => _loading = true);
    try {
      final res = await context.read<SessionController>().requestSmsCode(_digitsOnly(_phone.text));
      if (!mounted) return;
      setState(() {
        _step = 'code';
        _isNewUser = res.isNewUser;
        _showReferral = res.isNewUser;
        _resendLeft = 60;
        _code.clear();
        if (!res.isNewUser) _referral.clear();
      });
      if (res.debugCode != null) {
        _applyCodeDigits(res.debugCode!);
        _showSnack('Локально: код ${res.debugCode}');
      }
      _tickResend();
      _showSnack(res.isNewUser ? 'Код отправлен — завершите регистрацию' : 'Код отправлен');
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

  void _onCodeChanged(String raw) {
    final digits = _digitsOnly(raw).substring(0, _digitsOnly(raw).length.clamp(0, 6));
    _applyCodeDigits(digits);
    if (digits.length == 6 && !_loading && _offerAccepted && !_showReferral) {
      _tryAutoSubmitCode();
    }
  }

  void _tryAutoSubmitCode() {
    if (_codeAutoSubmitScheduled) return;
    _codeAutoSubmitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeAutoSubmitScheduled = false;
      if (mounted) _confirmCode();
    });
  }

  Future<void> _confirmCode() async {
    if (!_ensureOfferAccepted()) return;
    if (!_phoneIsComplete) {
      _showSnack('Введите номер телефона');
      return;
    }
    final code = _codeDigits;
    if (code.length != 6) {
      _showSnack('Введите 6 цифр кода');
      return;
    }
    final ref = _showReferral ? _digitsOnly(_referral.text).substring(0, _digitsOnly(_referral.text).length.clamp(0, 5)) : '';
    setState(() => _loading = true);
    try {
      await context.read<SessionController>().loginWithSms(
            digits9: _digitsOnly(_phone.text),
            code: code,
            ref: ref,
          );
      if (mounted) {
        _showSnack(_isNewUser ? 'Регистрация завершена' : 'Вход выполнен');
      }
    } catch (e) {
      _showSnack('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openOfferUrl() async {
    final uri = Uri.parse(AppConfig.offerUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildPhoneHelp(Brightness brightness) {
    final d = _digitsOnly(_phone.text);
    if (d.isEmpty) return const SizedBox.shrink();
    if (d.length == 9 && TjPhone.isValidMobile(d)) {
      final op = TjPhone.operatorName(d);
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          op != null ? 'Номер корректный · $op' : 'Номер корректный',
          style: TextStyle(
            fontSize: 14,
            color: AuthTheme.successGreen.withValues(alpha: brightness == Brightness.dark ? 0.95 : 1),
          ),
        ),
      );
    }
    if (d.length == 9) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          TjPhone.validationHint(),
          style: const TextStyle(fontSize: 13, color: AuthTheme.requiredRed),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Введите ещё ${9 - d.length} цифр',
        style: const TextStyle(fontSize: 14, color: AuthTheme.requiredRed),
      ),
    );
  }

  Widget _buildOfferRow(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final textColor = dark ? Colors.white.withValues(alpha: 0.88) : AuthTheme.textLight.withValues(alpha: 0.88);
    return InkWell(
      onTap: () => _setOfferAccepted(!_offerAccepted),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuthOfferCircleToggle(
              value: _offerAccepted,
              dark: dark,
              onChanged: _setOfferAccepted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 14, color: textColor, height: 1.45),
                    children: [
                      const TextSpan(text: 'Я принимаю условия '),
                      TextSpan(
                        text: 'оферты',
                        style: const TextStyle(color: AuthTheme.offerLink, fontWeight: FontWeight.w500),
                        recognizer: TapGestureRecognizer()..onTap = _openOfferUrl,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required Brightness brightness,
    required VoidCallback? onPressed,
    required String label,
  }) {
    final enabled = onPressed != null && !_loading;
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: FilledButton(
        onPressed: _loading ? null : onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: enabled ? AuthTheme.primary : AuthTheme.disabledBtn(brightness),
          disabledBackgroundColor: AuthTheme.disabledBtn(brightness),
          foregroundColor: enabled ? Colors.white : Colors.white.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  String get _cardTitle {
    if (_step == 'code' && _isNewUser) return 'Регистрация';
    return 'Вход';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final pageBg = AuthTheme.pageBg(brightness);
    final cardBg = AuthTheme.cardBg(brightness);
    final textColor = AuthTheme.text(brightness);
    final muted = AuthTheme.textMuted(brightness);
    final borderColor = AuthTheme.border(brightness);
    final inputBg = AuthTheme.inputBg(brightness);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: TojirAuthBrandLogo(),
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
                      padding: EdgeInsets.fromLTRB(24, isSmall ? 72 : 24, 24, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 260),
                                  child: Text(
                                    'Быстро и удобно — начните за минуту',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                      color: textColor.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 25),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                  color: cardBg,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        _cardTitle,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: textColor,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Divider(height: 1, color: borderColor),
                                      const SizedBox(height: 24),
                                      if (_step == 'phone') ...[
                                        Text.rich(
                                          TextSpan(
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: textColor,
                                            ),
                                            children: const [
                                              TextSpan(text: '* ', style: TextStyle(color: AuthTheme.requiredRed)),
                                              TextSpan(text: 'Телефон'),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: borderColor),
                                            color: inputBg,
                                          ),
                                          child: Row(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
                                                child: Text(
                                                  '+992',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                    color: textColor,
                                                  ),
                                                ),
                                              ),
                                              Container(width: 1, height: 22, color: borderColor),
                                              Expanded(
                                                child: TextField(
                                                  controller: _phone,
                                                  keyboardType: TextInputType.phone,
                                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s]'))],
                                                  style: TextStyle(fontSize: 16, color: textColor),
                                                  decoration: InputDecoration(
                                                    prefixIcon: Icon(
                                                      Icons.phone_android_outlined,
                                                      color: muted,
                                                      size: 18,
                                                    ),
                                                    hintText: '90 123 45 67',
                                                    hintStyle: TextStyle(fontSize: 16, color: muted),
                                                    border: InputBorder.none,
                                                    isDense: true,
                                                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        _buildPhoneHelp(brightness),
                                        const SizedBox(height: 12),
                                        _buildOfferRow(brightness),
                                        const SizedBox(height: 16),
                                        _buildPrimaryButton(
                                          brightness: brightness,
                                          onPressed: _offerAccepted ? _requestCode : null,
                                          label: 'Получить код',
                                        ),
                                      ],
                                      if (_step == 'code') ...[
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Код из SMS',
                                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textColor),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _code,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s]'))],
                                          autofillHints: const [AutofillHints.oneTimeCode],
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 12,
                                            color: textColor,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                          decoration: InputDecoration(
                                            hintText: '000000',
                                            hintStyle: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: 6,
                                              color: muted.withValues(alpha: 0.35),
                                            ),
                                            filled: true,
                                            fillColor: inputBg,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide(color: borderColor),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide(color: borderColor),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: const BorderSide(color: AuthTheme.primary, width: 2),
                                            ),
                                          ),
                                          onChanged: _onCodeChanged,
                                        ),
                                        if (_showReferral) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'Реферальный код',
                                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textColor),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: _referral,
                                            keyboardType: TextInputType.number,
                                            maxLength: 5,
                                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                            style: TextStyle(fontSize: 16, color: textColor),
                                            decoration: InputDecoration(
                                              counterText: '',
                                              hintText: 'Например: 4827',
                                              hintStyle: TextStyle(fontSize: 16, color: muted),
                                              filled: true,
                                              fillColor: inputBg,
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                borderSide: BorderSide(color: borderColor),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                borderSide: BorderSide(color: borderColor),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                borderSide: const BorderSide(color: AuthTheme.primary, width: 2),
                                              ),
                                            ),
                                            onChanged: (v) {
                                              final d = _digitsOnly(v).substring(0, _digitsOnly(v).length.clamp(0, 5));
                                              if (_referral.text != d) {
                                                _referral.value = TextEditingValue(
                                                  text: d,
                                                  selection: TextSelection.collapsed(offset: d.length),
                                                );
                                              }
                                            },
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              'Необязательно, если есть код приглашения',
                                              style: TextStyle(fontSize: 12, color: muted),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        _buildOfferRow(brightness),
                                        const SizedBox(height: 16),
                                        _buildPrimaryButton(
                                          brightness: brightness,
                                          onPressed: _offerAccepted ? _confirmCode : null,
                                          label: _isNewUser ? 'Зарегистрироваться' : 'Войти',
                                        ),
                                        const SizedBox(height: 10),
                                        Center(
                                          child: _resendLeft > 0
                                              ? Text(
                                                  'Отправить ещё код ($_resendLeftс)',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontSize: 13, color: muted),
                                                )
                                              : TextButton(
                                                  onPressed: _loading ? null : _requestCode,
                                                  style: TextButton.styleFrom(
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                  child: const Text(
                                                    'Отправить ещё код',
                                                    style: TextStyle(fontSize: 13, color: AuthTheme.primary),
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 40,
                                          child: TextButton(
                                            onPressed: _loading
                                                ? null
                                                : () {
                                                    setState(() {
                                                      _step = 'phone';
                                                      _isNewUser = false;
                                                      _showReferral = false;
                                                      _code.clear();
                                                      _referral.clear();
                                                    });
                                                  },
                                            style: TextButton.styleFrom(
                                              foregroundColor: textColor,
                                              backgroundColor: dark
                                                  ? Colors.white.withValues(alpha: 0.06)
                                                  : const Color(0xFFE2E8F0),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                side: BorderSide(color: borderColor),
                                              ),
                                            ),
                                            child: const Text('Сменить номер', style: TextStyle(fontSize: 14)),
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
