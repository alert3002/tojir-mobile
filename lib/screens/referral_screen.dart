import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/skeleton_loading.dart';

const _heroGradientStart = Color(0xFF1E2440);
const _heroGradientEnd = Color(0xFF171F33);
const _cardBg = Color(0xFF151D2E);
const _purple = Color(0xFF8B5CF6);
const _purpleTag = Color(0xFF6D28D9);
const _blue = Color(0xFF2563EB);
const _earnedGreen = Color(0xFF4ADE80);

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '');
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

String _formatMoneyRu(double n) {
  final neg = n < 0;
  final abs = neg ? -n : n;
  final s = abs.toStringAsFixed(2);
  final dot = s.indexOf('.');
  final intPart = s.substring(0, dot);
  final dec = s.substring(dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('\u00A0');
    buf.write(intPart[i]);
  }
  return '${neg ? '−' : ''}${buf.toString()}$dec';
}

String _fmtMoney(dynamic v) {
  final n = _asDouble(v);
  if (n == null) return '—';
  return _formatMoneyRu(n);
}

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool loading = true;
  String? loadError;
  Map<String, dynamic>? data;
  bool becomeLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReferrals());
  }

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Theme.of(context).colorScheme.error : null),
    );
  }

  Future<void> _loadReferrals() async {
    final u = _user;
    if (u == null) {
      setState(() {
        data = null;
        loading = false;
      });
      return;
    }
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final res = await context.read<ApiClient>().get('me/referrals/');
      if (!mounted) return;
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body.isEmpty ? '{}' : res.body);
        final detail = body is Map ? body['detail']?.toString() : null;
        throw Exception(detail ?? 'Не удалось загрузить список');
      }
      final j = jsonDecode(res.body);
      setState(() {
        data = j is Map<String, dynamic> ? j : {};
        loadError = null;
      });
    } catch (e) {
      setState(() {
        data = null;
        loadError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _referralLink(Map<String, dynamic>? user) {
    final code = (user?['referral_code'] ?? '').toString();
    if (code.isEmpty) return '';
    return 'https://tojir.tj/login?ref=$code';
  }

  Future<void> _copyLink(String link) async {
    if (link.isEmpty) {
      _snack('Реферальный код ещё не сформирован', error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    _snack('Ссылка скопирована');
  }

  Future<void> _becomeBusinessman() async {
    setState(() => becomeLoading = true);
    try {
      await context.read<SessionController>().becomeBusinessman();
      if (!mounted) return;
      _snack('Вы бизнесмен. Создайте склад в профиле.');
      Navigator.of(context).pushNamedAndRemoveUntil('/profile', (r) => r.isFirst);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => becomeLoading = false);
    }
  }

  Widget _becomeBusinessmanCard() {
    if ((_user?['role'] as String?) != 'client') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.storefront_outlined, size: 26, color: _blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Вести бизнес', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Склад, продажи, магазины и отчёты — после переключения роли на бизнесмена.',
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55), height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: becomeLoading ? null : _becomeBusinessman,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: becomeLoading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Стать бизнесменом'),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(Map<String, dynamic>? user, int bonusPercent, int inviteCount, double totalEarned, String link) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_heroGradientStart, _heroGradientEnd],
            ),
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [_purple.withValues(alpha: 0.35), _purpleTag.withValues(alpha: 0.2)],
                  ),
                  border: Border.all(color: _purple.withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFC4B5FD), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 13, height: 1.45, color: Colors.white.withValues(alpha: 0.88)),
                    children: [
                      const TextSpan(text: 'Делитесь ссылкой — получайте '),
                      TextSpan(text: '$bonusPercent%', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFC4B5FD))),
                      const TextSpan(text: ' с каждого пополнения баланса приглашённого.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statBox('Код', (user?['referral_code'] ?? '—').toString(), mono: true)),
            const SizedBox(width: 8),
            Expanded(child: _statBox('Приглашено', '$inviteCount')),
          ],
        ),
        const SizedBox(height: 8),
        _statBox('Заработано', '${_formatMoneyRu(totalEarned)} TJS', earned: true),
        const SizedBox(height: 12),
        TextField(
          readOnly: true,
          controller: TextEditingController(text: link),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.25),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _copyLink(link),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Копировать'),
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value, {bool mono = false, bool earned = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C111C).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: earned ? _earnedGreen : Colors.white,
              fontFamily: mono ? 'monospace' : null,
              letterSpacing: mono ? 0.5 : 0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _referralCard(Map<String, dynamic> r) {
    final joined = r['date_joined']?.toString();
    final date = joined != null && joined.length >= 10 ? joined.substring(0, 10) : '—';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: _blue.withValues(alpha: 0.15),
                  border: Border.all(color: _blue.withValues(alpha: 0.25)),
                ),
                child: Icon(Icons.person_outline_rounded, size: 18, color: Colors.white.withValues(alpha: 0.75)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (r['name'] ?? '—').toString(),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      (r['phone_display'] ?? '—').toString(),
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metaCol('Регистрация', date)),
              const SizedBox(width: 8),
              Expanded(child: _metaCol('Пополнено', _fmtMoney(r['total_topup_tjs']))),
              const SizedBox(width: 8),
              Expanded(child: _metaCol('Вам', _fmtMoney(r['your_bonus_tjs']), green: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaCol(String label, String value, {bool green = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45))),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: green ? _earnedGreen : Colors.white.withValues(alpha: 0.9)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;

    if (u == null || !canAccessSection(u, 'referral', null)) {
      return const AppScaffold(child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))));
    }

    final bonusPercent = _asInt(data?['bonus_percent']) ?? 10;
    final inviteCount = _asInt(data?['invite_count']) ?? _asInt(u['referral_count']) ?? 0;
    final totalEarned = _asDouble(data?['total_earned_tjs']) ?? 0;
    final link = _referralLink(u);
    final referrals = (data?['referrals'] is List) ? (data!['referrals'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadReferrals,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            children: [
              Row(
                children: [
                  Icon(Icons.group_add_rounded, size: 22, color: cs.onSurface),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Реферал', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _purpleTag.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _purple.withValues(alpha: 0.45)),
                    ),
                    child: Text('$bonusPercent% бонус', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFD8B4FE))),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _heroCard(u, bonusPercent, inviteCount, totalEarned, link),
              const SizedBox(height: 16),
              _becomeBusinessmanCard(),
              Row(
                children: [
                  const Text('Список приглашённых', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (inviteCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('$inviteCount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (loading)
                const SkeletonListBlock(rows: 4)
              else if (loadError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Text(loadError!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadReferrals, child: const Text('Повторить')),
                    ],
                  ),
                )
              else if (referrals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Пока никто не зарегистрировался',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                )
              else
                for (var i = 0; i < referrals.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _referralCard(referrals[i]),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
