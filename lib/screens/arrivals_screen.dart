import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/number_format.dart';
import '../utils/permissions.dart';
import '../utils/product_scan_utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/quick_date_range_chips.dart';
import '../widgets/skeleton_loading.dart';

const _blue = Color(0xFF2563EB);
const _surface = Color(0xFF151D2E);
const _rowBg = Color(0xFF1A2438);
const _muted = Color(0xFF94A3B8);
const _border = Color(0x1AFFFFFF);
const _historyMobilePageSize = 15;

class ArrivalsScreen extends StatefulWidget {
  const ArrivalsScreen({super.key});

  @override
  State<ArrivalsScreen> createState() => _ArrivalsScreenState();
}

class _ArrivalsScreenState extends State<ArrivalsScreen> with SingleTickerProviderStateMixin {
  bool loadingRefs = false;
  bool savingArrival = false;
  bool historyLoading = false;

  List<Map<String, dynamic>> products = const [];
  List<Map<String, dynamic>> suppliers = const [];
  List<Map<String, dynamic>> categories = const [];

  int? productCategoryId;
  double usdToTjs = 11.5;

  late TabController _tabCtrl;

  final List<_ArrivalRow> rows = <_ArrivalRow>[
    _ArrivalRow(
      quantity: 1,
      unit: 'pcs',
      currency: 'TJS',
      condition: 'new',
      isDebt: false,
      date: DateTime.now(),
    ),
  ];
  final TextEditingController commentCtrl = TextEditingController();

  // History
  DateTimeRange? historyRange;
  String? historyPreset = 'month';
  final TextEditingController historySearchCtrl = TextEditingController();
  List<Map<String, dynamic>> history = const [];
  int historyMobilePage = 1;

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this)..addListener(() { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      historyPreset = 'month';
      historyRange = _historyRangeForPreset('month');
      await _loadRate();
      await _loadRefs();
      await _loadHistory();
    });
  }

  DateTimeRange _historyRangeForPreset(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (key) {
      case 'today':
        return DateTimeRange(start: today, end: today);
      case 'week':
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case 'month':
        return DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
      default:
        return DateTimeRange(start: today, end: today);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    commentCtrl.dispose();
    historySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRate() async {
    try {
      final res = await context.read<ApiClient>().get('inventory/rate/');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final v = d['usd_to_tjs'];
        final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
        if (n != null && n > 0) setState(() => usdToTjs = n);
      }
    } catch (_) {}
  }

  void _handleScan(int rowIdx, String raw) {
    final code = normalizeScanCode(raw);
    if (code.isEmpty) return;
    final found = findWarehouseProductByCode(code, products);
    if (found == null) {
      _snack('Товар не найден — выберите вручную или создайте новый');
      return;
    }
    final id = _asInt(found['id']);
    if (id == null) return;
    final sale = found['sale_price'];
    final saleN = sale is num ? sale.toDouble() : double.tryParse(sale?.toString() ?? '');
    setState(() {
      rows[rowIdx] = rows[rowIdx].copyWith(
        productId: id,
        barcode: code,
        salePrice: (saleN != null && saleN > 0) ? saleN : rows[rowIdx].salePrice,
      );
    });
    _snack('Найден: ${found['name']}');
  }

  String? _validateSalePrice(double? salePrice, double? purchasePrice, String currency) {
    if (salePrice == null || salePrice <= 0) return 'Укажите цену продажи';
    final costTjs = currency == 'USD' && usdToTjs > 0 ? (purchasePrice ?? 0) * usdToTjs : (purchasePrice ?? 0);
    if (costTjs > 0 && salePrice < costTjs) {
      return 'Не ниже закупки (${costTjs.toStringAsFixed(2)} TJS)';
    }
    return null;
  }

  void _snack(String msg, {bool error = false}) {
    final text = msg.replaceFirst('Exception: ', '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text.isEmpty ? (error ? 'Ошибка' : 'Готово') : text),
        backgroundColor: error ? const Color(0xFFDC2626) : null,
      ),
    );
  }

  Future<void> _loadRefs() async {
    setState(() => loadingRefs = true);
    try {
      final api = context.read<ApiClient>();
      final res = await Future.wait([
        api.get('inventory/products/'),
        api.get('inventory/categories/'),
        api.get('inventory/suppliers/'),
      ]);
      if (!mounted) return;

      products = _asListOfMap(res[0]);
      categories = _asListOfMap(res[1]);
      suppliers = _asListOfMap(res[2]);

      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        products = const [];
        categories = const [];
        suppliers = const [];
      });
    } finally {
      if (mounted) setState(() => loadingRefs = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => historyLoading = true);
    try {
      final api = context.read<ApiClient>();
      final qp = <String, String>{};
      if (historyRange != null) {
        qp['date_from'] = _fmtYmd(historyRange!.start);
        qp['date_to'] = _fmtYmd(historyRange!.end);
      }
      final hs = historySearchCtrl.text.trim();
      if (hs.isNotEmpty) qp['search'] = hs;

      final path = qp.isEmpty ? 'inventory/arrival-items/' : 'inventory/arrival-items/?${Uri(queryParameters: qp).query}';
      final res = await api.get(path);
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => history = _asListFromBody(res.body));
      } else {
        setState(() => history = const []);
      }
    } catch (_) {
      if (mounted) setState(() => history = const []);
    } finally {
      if (mounted) setState(() => historyLoading = false);
    }
  }

  Future<void> _saveArrival() async {
    final u = _user;
    if (u == null) return;
    final warehouseId = _asInt(u['warehouse']) ?? _asInt(u['warehouse_id']);
    if (warehouseId == null) {
      _snack('Укажите склад в профиле', error: true);
      return;
    }
    if (rows.isEmpty) {
      _snack('Добавьте хотя бы одну строку', error: true);
      return;
    }
    for (final r in rows) {
      if (r.productId == null) {
        _snack('Выберите товар во всех строках', error: true);
        return;
      }
      if (r.date == null) {
        _snack('Укажите дату прихода во всех строках', error: true);
        return;
      }
      if (r.price == null || r.price! < 0) {
        _snack('Укажите цену закупки во всех строках', error: true);
        return;
      }
      final saleErr = _validateSalePrice(r.salePrice, r.price, r.currency);
      if (saleErr != null) {
        _snack(saleErr, error: true);
        return;
      }
      if (r.quantity <= 0) {
        _snack('Количество должно быть больше 0', error: true);
        return;
      }
      if (r.isDebt && r.supplierId == null) {
        _snack('Для строки "В долг" выберите поставщика', error: true);
        return;
      }
    }

    setState(() => savingArrival = true);
    try {
      final api = context.read<ApiClient>();
      final payload = <String, dynamic>{
        'warehouse': warehouseId,
        'comment': commentCtrl.text.trim(),
        'items': rows.map((r) {
          return {
            'product': r.productId,
            'arrival_date': _fmtYmd(r.date!),
            'quantity': r.quantity,
            'unit': r.unit,
            'unit_price': r.price,
            'currency': r.currency,
            'supplier': r.supplierId,
            'is_debt': r.isDebt,
            'condition': r.condition,
            'sale_price': r.salePrice,
            if (r.barcode != null && r.barcode!.trim().isNotEmpty) 'barcode': r.barcode!.trim(),
          };
        }).toList(),
      };

      final res = await api.post('inventory/arrivals/', body: payload);
      if (!mounted) return;
      if (res.statusCode != 200 && res.statusCode != 201) {
        final data = _tryJson(res.body);
        final msg = (data is Map && data['detail'] != null) ? data['detail'].toString() : 'Не удалось сохранить поступление';
        throw Exception(msg);
      }

      _snack('Поступление сохранено');
      setState(() {
        rows
          ..clear()
          ..add(_ArrivalRow(quantity: 1, unit: 'pcs', currency: 'TJS', condition: 'new', isDebt: false, date: DateTime.now()));
        commentCtrl.text = '';
      });
      await _loadHistory();
      if (mounted) _tabCtrl.animateTo(1);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => savingArrival = false);
    }
  }

  Future<void> _openProductPicker(int rowIdx) async {
    final current = rows[rowIdx].productId;
    final selectedIds = rows.map((r) => r.productId).whereType<int>().toSet();
    final options = products.where((p) {
      final id = _asInt(p['id']);
      if (id == null) return false;
      return !selectedIds.contains(id) || id == current;
    }).toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickerSheet(
        title: 'Товар',
        hint: 'Имя / модель / артикул',
        rows: options,
        label: warehouseProductOptionLabel,
        onTap: (m) {
          final id = _asInt(m['id']);
          if (id == null) return;
          setState(() => rows[rowIdx] = rows[rowIdx].copyWith(productId: id));
          Navigator.of(ctx).pop();
        },
        footerActionLabel: 'Новый товар',
        onFooterAction: () async {
          Navigator.of(ctx).pop();
          await _openCreateProduct(rowIdx);
        },
      ),
    );
  }

  Future<void> _openSupplierPicker(int rowIdx) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickerSheet(
        title: 'Поставщик',
        hint: 'Поиск по имени',
        rows: suppliers,
        label: (m) => (m['name'] ?? '—').toString(),
        trailing: (m) => IconButton(
          tooltip: 'Удалить',
          onPressed: () async {
            final sid = _asInt(m['id']);
            if (sid == null) return;
            final name = (m['name'] ?? '—').toString();
            final ok = await showDialog<bool>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('Удалить поставщика?'),
                content: Text('Поставщик «$name» будет удалён из списка.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Отмена')),
                  FilledButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Удалить')),
                ],
              ),
            );
            if (ok != true) return;
            try {
              if (!mounted) return;
              final api = context.read<ApiClient>();
              final res = await api.delete('inventory/suppliers/$sid/');
              if (!(res.statusCode == 200 || res.statusCode == 204)) {
                throw Exception('Не удалось удалить поставщика');
              }
            } catch (_) {}
            setState(() {
              suppliers = suppliers.where((x) => _asInt(x['id']) != sid).toList();
              for (var i = 0; i < rows.length; i++) {
                if (rows[i].supplierId == sid) rows[i] = rows[i].copyWith(supplierId: null);
              }
            });
          },
          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
        ),
        onTap: (m) {
          final id = _asInt(m['id']);
          if (id == null) return;
          setState(() => rows[rowIdx] = rows[rowIdx].copyWith(supplierId: id, isDebt: true));
          Navigator.of(ctx).pop();
        },
        footerActionLabel: 'Новый поставщик',
        onFooterAction: () async {
          Navigator.of(ctx).pop();
          await _openCreateSupplier(rowIdx);
        },
      ),
    );
  }

  Future<void> _openCreateSupplier(int rowIdx) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return _ModalSheet(
          title: 'Новый поставщик',
          child: Column(
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Имя поставщика *')),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Телефон',
                  hintText: '901234567',
                  helperText: '9 цифр, без +992',
                ),
                keyboardType: TextInputType.number,
                maxLength: 9,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 10),
              TextField(controller: noteCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Заметка')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Сохранить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dark ? Colors.white : null,
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      noteCtrl.dispose();
      return;
    }
    try {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) throw Exception('Введите имя поставщика');
      final phone = phoneCtrl.text.trim();
      if (phone.isNotEmpty && phone.length != 9) {
        throw Exception('Телефон: ровно 9 цифр (без +992)');
      }
      if (!mounted) return;
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/suppliers/',
        body: {'name': name, 'phone': phone, 'note': noteCtrl.text.trim()},
      );
      final data = _tryJson(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        final msg = (data is Map && data['detail'] != null) ? data['detail'].toString() : 'Не удалось создать поставщика';
        throw Exception(msg);
      }
      if (data is! Map<String, dynamic>) throw Exception('Неверный ответ сервера');
      setState(() {
        suppliers = [...suppliers, data];
        rows[rowIdx] = rows[rowIdx].copyWith(supplierId: _asInt(data['id']), isDebt: true);
      });
      _snack('Поставщик добавлен');
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _openCreateProduct(int rowIdx) async {
    final nameCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    String? color;
    String? memory;
    String? ram;
    final sizeCtrl = TextEditingController();
    int? category;
    int? subcategory;

    bool showBrand = false;
    bool showColor = false;
    bool showMemory = false;
    bool showRam = false;
    bool showSize = false;

    void recomputeExtra() {
      final activeId = subcategory ?? category;
      if (activeId == null) {
        showBrand = false;
        showColor = false;
        showMemory = false;
        showRam = false;
        showSize = false;
        return;
      }
      final cat = categories.firstWhere((c) => _asInt(c['id']) == activeId, orElse: () => const {});
      final name = (cat['name'] ?? '').toString().toLowerCase();
      final isPhone = RegExp(r'телефон|смартфон|phone|смарт').hasMatch(name);
      final isClothesOrShoes = RegExp(r'одежд|обув|кроссовк|ботинк|куртк|брюк|футболк|плать|юбк').hasMatch(name);
      final isFurnitureOrBoards = RegExp(r'мебел|стол|стул|шкаф|тахт|матрас|диван').hasMatch(name);
      final isAuto = RegExp(r'авто|запчаст|шина|масл|аккумулятор|колес').hasMatch(name);
      showBrand = isPhone || isClothesOrShoes || isAuto;
      showColor = true;
      showMemory = isPhone;
      showRam = isPhone;
      showSize = isPhone || isClothesOrShoes || isFurnitureOrBoards;
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final dark = Theme.of(ctx).brightness == Brightness.dark;
          final parents = categories.where((c) => c['parent'] == null).toList();
          final children = categories.where((c) => _asInt(c['parent']) == category).toList();
          return _ModalSheet(
            title: 'Новый товар',
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey<int?>(category),
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, labelText: 'Категория'),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('—')),
                    ...parents.map((c) {
                      final id = _asInt(c['id']);
                      return DropdownMenuItem<int>(value: id, child: Text((c['name'] ?? '—').toString()));
                    }),
                  ],
                  onChanged: (v) {
                    setLocal(() {
                      category = v;
                      subcategory = null;
                      productCategoryId = v;
                      recomputeExtra();
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: ValueKey<String>('sub_${subcategory}_$category'),
                  initialValue: subcategory,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, labelText: 'Подкатегория'),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('—')),
                    ...children.map((c) {
                      final id = _asInt(c['id']);
                      return DropdownMenuItem<int>(value: id, child: Text((c['name'] ?? '—').toString()));
                    }),
                  ],
                  onChanged: (v) {
                    setLocal(() {
                      subcategory = v;
                      recomputeExtra();
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Название товара *')),
                const SizedBox(height: 10),
                TextField(controller: modelCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Модель (необязательно)')),
                const SizedBox(height: 10),
                TextField(controller: skuCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Артикул (SKU) *')),
                if (showBrand) ...[
                  const SizedBox(height: 10),
                  TextField(controller: brandCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Марка')),
                ],
                if (showColor) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String?>(color),
                    initialValue: color,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, labelText: 'Ранг (цвет)'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('—')),
                      DropdownMenuItem(value: 'black', child: Text('Чёрный')),
                      DropdownMenuItem(value: 'white', child: Text('Белый')),
                      DropdownMenuItem(value: 'gray', child: Text('Серый')),
                      DropdownMenuItem(value: 'silver', child: Text('Серебристый')),
                      DropdownMenuItem(value: 'blue', child: Text('Синий')),
                      DropdownMenuItem(value: 'light-blue', child: Text('Голубой')),
                      DropdownMenuItem(value: 'red', child: Text('Красный')),
                      DropdownMenuItem(value: 'green', child: Text('Зелёный')),
                      DropdownMenuItem(value: 'yellow', child: Text('Жёлтый')),
                      DropdownMenuItem(value: 'orange', child: Text('Оранжевый')),
                      DropdownMenuItem(value: 'brown', child: Text('Коричневый')),
                      DropdownMenuItem(value: 'pink', child: Text('Розовый')),
                      DropdownMenuItem(value: 'violet', child: Text('Фиолетовый')),
                    ],
                    onChanged: (v) => setLocal(() => color = v),
                  ),
                ],
                if (showMemory) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String?>(memory),
                    initialValue: memory,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, labelText: 'Память'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('—')),
                      DropdownMenuItem(value: '16GB', child: Text('16 ГБ')),
                      DropdownMenuItem(value: '32GB', child: Text('32 ГБ')),
                      DropdownMenuItem(value: '64GB', child: Text('64 ГБ')),
                      DropdownMenuItem(value: '128GB', child: Text('128 ГБ')),
                      DropdownMenuItem(value: '256GB', child: Text('256 ГБ')),
                      DropdownMenuItem(value: '512GB', child: Text('512 ГБ')),
                      DropdownMenuItem(value: '1TB', child: Text('1 ТБ')),
                    ],
                    onChanged: (v) => setLocal(() => memory = v),
                  ),
                ],
                if (showRam) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String?>(ram),
                    initialValue: ram,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, labelText: 'RAM'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('—')),
                      DropdownMenuItem(value: '2GB', child: Text('2 ГБ')),
                      DropdownMenuItem(value: '3GB', child: Text('3 ГБ')),
                      DropdownMenuItem(value: '4GB', child: Text('4 ГБ')),
                      DropdownMenuItem(value: '6GB', child: Text('6 ГБ')),
                      DropdownMenuItem(value: '8GB', child: Text('8 ГБ')),
                      DropdownMenuItem(value: '12GB', child: Text('12 ГБ')),
                      DropdownMenuItem(value: '16GB', child: Text('16 ГБ')),
                    ],
                    onChanged: (v) => setLocal(() => ram = v),
                  ),
                ],
                if (showSize) ...[
                  const SizedBox(height: 10),
                  TextField(controller: sizeCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Размер')),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Сохранить товар'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(foregroundColor: dark ? Colors.white : null),
                        child: const Text('Отмена'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      modelCtrl.dispose();
      skuCtrl.dispose();
      brandCtrl.dispose();
      sizeCtrl.dispose();
      return;
    }
    try {
      final name = nameCtrl.text.trim();
      final sku = skuCtrl.text.trim();
      if (name.isEmpty) throw Exception('Введите название');
      if (sku.isEmpty) throw Exception('Введите SKU');
      if (!mounted) return;
      final api = context.read<ApiClient>();
      final warehouseId = _asInt(_user?['warehouse']) ?? _asInt(_user?['warehouse_id']);
      final payload = {
        'name': name,
        'model': modelCtrl.text.trim(),
        'sku': sku,
        'category': category,
        'subcategory': subcategory,
        'warehouse': warehouseId,
        'brand': brandCtrl.text.trim(),
        'color': color ?? '',
        'memory': memory ?? '',
        'ram': ram ?? '',
        'size': sizeCtrl.text.trim(),
      };
      final res = await api.post('inventory/products/', body: payload);
      final data = _tryJson(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        final msg = (data is Map)
            ? ((data['sku'] is List && (data['sku'] as List).isNotEmpty) ? (data['sku'] as List).first.toString() : (data['detail'] ?? data['sku'] ?? 'Не удалось создать товар').toString())
            : 'Не удалось создать товар';
        throw Exception(msg);
      }
      if (data is! Map<String, dynamic>) throw Exception('Неверный ответ сервера');
      setState(() {
        products = [...products, data];
        rows[rowIdx] = rows[rowIdx].copyWith(productId: _asInt(data['id']));
      });
      _snack('Товар добавлен');
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      nameCtrl.dispose();
      modelCtrl.dispose();
      skuCtrl.dispose();
      brandCtrl.dispose();
      sizeCtrl.dispose();
    }
  }

  String? get _warehouseLabel {
    final u = _user;
    if (u == null) return null;
    final name = (u['warehouse_name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final addr = (u['warehouse_address'] ?? '').toString().trim();
    return addr.isEmpty ? name : '$name, $addr';
  }

  List<Map<String, dynamic>> get _historySlice {
    final start = (historyMobilePage - 1) * _historyMobilePageSize;
    return history.skip(start).take(_historyMobilePageSize).toList();
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (u == null || !canAccessSection(u, 'arrivals', null)) {
      return const AppScaffold(
        child: SafeArea(top: false, child: Center(child: Text('Нет доступа'))),
      );
    }

    final historyTabLabel = 'История${history.isEmpty ? '' : ' (${history.length})'}';

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Поступление', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  TabBar(
                    controller: _tabCtrl,
                    labelColor: const Color(0xFF60A5FA),
                    unselectedLabelColor: _muted,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                    indicatorColor: _blue,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [
                      const Tab(text: 'Добавить'),
                      Tab(text: historyTabLabel),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildAddTab(cs, dark),
                  _buildHistoryTab(cs, dark),
                ],
              ),
            ),
            if (_tabCtrl.index == 0)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                    stops: const [0.0, 0.28],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: FilledButton(
                    onPressed: savingArrival || _warehouseLabel == null ? null : _saveArrival,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      shadowColor: _blue.withValues(alpha: 0.45),
                    ),
                    child: Text(
                      savingArrival ? 'Сохранение…' : 'Сохранить поступление',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTab(ColorScheme cs, bool dark) {
    final warehouseLabel = _warehouseLabel;
    return RefreshIndicator(
      onRefresh: () async {
        await _loadRate();
        await _loadRefs();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          if (warehouseLabel != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.35)),
              ),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                  children: [
                    const TextSpan(text: 'Склад: ', style: TextStyle(color: _muted)),
                    TextSpan(text: warehouseLabel),
                  ],
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
              ),
              child: Text('Укажите склад в профиле', style: TextStyle(color: Colors.amber.shade400, fontSize: 13)),
            ),
          if (loadingRefs) const SkeletonListBlock(rows: 4),
          if (!loadingRefs)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: dark ? _surface : Theme.of(context).cardColor,
                border: Border.all(color: dark ? _border : Colors.black.withValues(alpha: 0.06)),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _ArrivalRowCard(
                      key: ValueKey('arrival_row_$i'),
                      index: i,
                      dark: dark,
                      cs: cs,
                      row: rows[i],
                      products: products,
                      suppliers: suppliers,
                      onScan: (code) => _handleScan(i, code),
                      onPickProduct: () => _openProductPicker(i),
                      onNewProduct: () => _openCreateProduct(i),
                      onPickSupplier: () => _openSupplierPicker(i),
                      onChanged: (next) => setState(() => rows[i] = next),
                      onDelete: rows.length <= 1 ? null : () => setState(() => rows.removeAt(i)),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => rows.add(_ArrivalRow(quantity: 1, unit: 'pcs', currency: 'TJS', condition: 'new', isDebt: false, date: DateTime.now()))),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ещё позиция'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface.withValues(alpha: 0.85),
                      side: BorderSide(color: dark ? _border : Colors.black.withValues(alpha: 0.12)),
                      minimumSize: const Size.fromHeight(40),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: commentCtrl,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Комментарий (необяз.)',
                      hintStyle: const TextStyle(color: _muted, fontSize: 13),
                      filled: true,
                      fillColor: dark ? Colors.white.withValues(alpha: 0.03) : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: dark ? _border : Colors.black.withValues(alpha: 0.1)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(ColorScheme cs, bool dark) {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dark ? _surface : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: dark ? _border : Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: historySearchCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          hintText: 'Товар или поставщик',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onSubmitted: (_) {
                          setState(() => historyMobilePage = 1);
                          _loadHistory();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => historyMobilePage = 1);
                        _loadHistory();
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(40, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                QuickDateRangeChips(
                  colorScheme: cs,
                  selected: historyPreset == 'custom' ? null : historyPreset,
                  showPeriod: false,
                  onToday: () {
                    setState(() {
                      historyPreset = 'today';
                      historyRange = _historyRangeForPreset('today');
                      historyMobilePage = 1;
                    });
                  },
                  onWeek: () {
                    setState(() {
                      historyPreset = 'week';
                      historyRange = _historyRangeForPreset('week');
                      historyMobilePage = 1;
                    });
                  },
                  onMonth: () {
                    setState(() {
                      historyPreset = 'month';
                      historyRange = _historyRangeForPreset('month');
                      historyMobilePage = 1;
                    });
                  },
                  onPeriod: () {},
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: historyRange,
                      locale: const Locale('ru'),
                    );
                    if (picked != null) {
                      setState(() {
                        historyPreset = 'custom';
                        historyRange = DateTimeRange(
                          start: DateTime(picked.start.year, picked.start.month, picked.start.day),
                          end: DateTime(picked.end.year, picked.end.month, picked.end.day),
                        );
                        historyMobilePage = 1;
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    historyRange == null
                        ? 'Дата от — Дата до'
                        : '${_fmtDmy(historyRange!.start)} — ${_fmtDmy(historyRange!.end)}',
                  ),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    setState(() => historyMobilePage = 1);
                    _loadHistory();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    minimumSize: const Size.fromHeight(36),
                  ),
                  child: const Text('Применить'),
                ),
              ],
            ),
          ),
          if (!historyLoading && history.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Записей: ${history.length}', style: TextStyle(fontSize: 12, color: _muted)),
          ],
          const SizedBox(height: 8),
          if (historyLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
          else if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Пока нет поступлений', style: TextStyle(color: _muted))),
            )
          else
            ..._historySlice.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _HistoryMobileCard(record: r, dark: dark, cs: cs),
            )),
          if (history.length > _historyMobilePageSize) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: historyMobilePage > 1 ? () => setState(() => historyMobilePage--) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('$historyMobilePage / ${(history.length / _historyMobilePageSize).ceil()}'),
                IconButton(
                  onPressed: historyMobilePage < (history.length / _historyMobilePageSize).ceil()
                      ? () => setState(() => historyMobilePage++)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrivalRowCard extends StatefulWidget {
  const _ArrivalRowCard({
    super.key,
    required this.index,
    required this.dark,
    required this.cs,
    required this.row,
    required this.products,
    required this.suppliers,
    required this.onScan,
    required this.onPickProduct,
    required this.onNewProduct,
    required this.onPickSupplier,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final bool dark;
  final ColorScheme cs;
  final _ArrivalRow row;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> suppliers;
  final ValueChanged<String> onScan;
  final VoidCallback onPickProduct;
  final VoidCallback onNewProduct;
  final VoidCallback onPickSupplier;
  final ValueChanged<_ArrivalRow> onChanged;
  final VoidCallback? onDelete;

  @override
  State<_ArrivalRowCard> createState() => _ArrivalRowCardState();
}

class _ArrivalRowCardState extends State<_ArrivalRowCard> {
  late TextEditingController _barcodeCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _saleCtrl;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _barcodeCtrl = TextEditingController(text: r.barcode ?? '');
    _qtyCtrl = TextEditingController(text: r.quantity % 1 == 0 ? r.quantity.toInt().toString() : r.quantity.toString());
    _priceCtrl = TextEditingController(text: r.price?.toStringAsFixed(2) ?? '0');
    _saleCtrl = TextEditingController(text: r.salePrice?.toStringAsFixed(2) ?? '');
  }

  @override
  void didUpdateWidget(covariant _ArrivalRowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.barcode != widget.row.barcode) _barcodeCtrl.text = widget.row.barcode ?? '';
    if (oldWidget.row.salePrice != widget.row.salePrice && widget.row.salePrice != null) {
      _saleCtrl.text = widget.row.salePrice!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _saleCtrl.dispose();
    super.dispose();
  }

  String _productLabel() {
    final pid = widget.row.productId;
    if (pid == null) return 'Выберите товар';
    final p = widget.products.firstWhere((x) => _asInt(x['id']) == pid, orElse: () => const {});
    return warehouseProductOptionLabel(p);
  }

  String _supplierLabel() {
    final sid = widget.row.supplierId;
    if (sid == null) return 'Выберите поставщика';
    final s = widget.suppliers.firstWhere((x) => _asInt(x['id']) == sid, orElse: () => const {});
    return (s['name'] ?? '—').toString();
  }

  InputDecoration _fieldDeco({String? hint}) {
    final dark = widget.dark;
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: _muted, fontSize: 13),
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.03) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: dark ? _border : Colors.black.withValues(alpha: 0.1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final dark = widget.dark;
    final cs = widget.cs;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: dark ? _rowBg : cs.surfaceContainerHighest,
        border: Border.all(color: dark ? _border : Colors.black.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Позиция ${widget.index + 1}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: cs.onSurface),
              ),
              const Spacer(),
              if (widget.onDelete != null)
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _label('IMEI / штрих-код'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: _fieldDeco(hint: 'Скан или ввод'),
                  onSubmitted: widget.onScan,
                  onChanged: (v) => widget.onChanged(row.copyWith(barcode: v)),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 38,
                child: OutlinedButton(
                  onPressed: () => widget.onScan(_barcodeCtrl.text),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(color: dark ? _border : Colors.black.withValues(alpha: 0.12)),
                    foregroundColor: cs.onSurface.withValues(alpha: 0.85),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Скан', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 38,
                width: 38,
                child: FilledButton(
                  onPressed: () => widget.onScan(_barcodeCtrl.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _label('Товар', required: true),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: dark ? Colors.white.withValues(alpha: 0.03) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: widget.onPickProduct,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dark ? _border : Colors.black.withValues(alpha: 0.1)),
                      ),
                      child: Text(
                        _productLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: row.productId == null ? _muted : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 38,
                child: OutlinedButton(
                  onPressed: widget.onNewProduct,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(color: dark ? _border : Colors.black.withValues(alpha: 0.12)),
                    foregroundColor: cs.onSurface.withValues(alpha: 0.85),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Новый', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Дата', required: true),
                    Material(
                      color: dark ? Colors.white.withValues(alpha: 0.03) : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            initialDate: row.date ?? DateTime.now(),
                            locale: const Locale('ru'),
                          );
                          if (picked != null) widget.onChanged(row.copyWith(date: picked));
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: dark ? _border : Colors.black.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.date == null ? '—' : _fmtDmy(row.date!),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Icon(Icons.calendar_today_outlined, size: 14, color: _muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Кол-во', required: true),
                    TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 13),
                      decoration: _fieldDeco(),
                      onChanged: (v) => widget.onChanged(row.copyWith(quantity: double.tryParse(v.replaceAll(',', '.')) ?? row.quantity)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Ед.'),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('unit_${widget.index}_${row.unit}'),
                      initialValue: row.unit,
                      isExpanded: true,
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                      decoration: _fieldDeco(),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('шт')),
                        DropdownMenuItem(value: 'L', child: Text('л')),
                        DropdownMenuItem(value: 'kg', child: Text('кг')),
                        DropdownMenuItem(value: 'ml', child: Text('мл')),
                        DropdownMenuItem(value: 'g', child: Text('г')),
                        DropdownMenuItem(value: 'm', child: Text('м')),
                        DropdownMenuItem(value: 'pack', child: Text('упак')),
                        DropdownMenuItem(value: 'box', child: Text('кор')),
                        DropdownMenuItem(value: 'bottle', child: Text('бут')),
                      ],
                      onChanged: (v) => widget.onChanged(row.copyWith(unit: v ?? 'pcs')),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Закупка', required: true),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 13),
                      decoration: _fieldDeco(hint: '0'),
                      onChanged: (v) => widget.onChanged(row.copyWith(price: double.tryParse(v.replaceAll(',', '.')))),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Вал.'),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>('cur_${widget.index}_${row.currency}'),
                      initialValue: row.currency,
                      isExpanded: true,
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                      decoration: _fieldDeco(),
                      items: const [
                        DropdownMenuItem(value: 'TJS', child: Text('с.')),
                        DropdownMenuItem(value: 'USD', child: Text(r'$')),
                      ],
                      onChanged: (v) => widget.onChanged(row.copyWith(currency: v ?? 'TJS')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _label('Цена продажи (TJS)', required: true),
          TextField(
            controller: _saleCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13),
            decoration: _fieldDeco(hint: 'Для кассы'),
            onChanged: (v) => widget.onChanged(row.copyWith(salePrice: double.tryParse(v.replaceAll(',', '.')))),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch.adaptive(
                value: row.isDebt,
                activeThumbColor: _blue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => widget.onChanged(row.copyWith(isDebt: v, supplierId: v ? row.supplierId : null)),
              ),
              const SizedBox(width: 4),
              Text('В долг у поставщика', style: TextStyle(fontSize: 12, color: _muted)),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: dark ? _border : Colors.black.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ConditionChip(
                      label: 'Новый',
                      selected: row.condition == 'new',
                      onTap: () => widget.onChanged(row.copyWith(condition: 'new')),
                    ),
                    _ConditionChip(
                      label: 'Б/У',
                      selected: row.condition == 'used',
                      onTap: () => widget.onChanged(row.copyWith(condition: 'used')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (row.isDebt) ...[
            const SizedBox(height: 4),
            _label('Поставщик', required: true),
            Material(
              color: dark ? Colors.white.withValues(alpha: 0.03) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: widget.onPickSupplier,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: dark ? _border : Colors.black.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _supplierLabel(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: row.supplierId == null ? _muted : cs.onSurface,
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, color: _muted, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: _muted),
          children: [
            TextSpan(text: text),
            if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFEF4444))),
          ],
        ),
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        color: selected ? _blue.withValues(alpha: 0.2) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? const Color(0xFF60A5FA) : _muted,
          ),
        ),
      ),
    );
  }
}

class _HistoryMobileCard extends StatelessWidget {
  const _HistoryMobileCard({required this.record, required this.dark, required this.cs});

  final Map<String, dynamic> record;
  final bool dark;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final subline = [record['product_model'], record['product_brand'], record['product_sku']].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
    final qty = record['quantity'];
    final qtyN = qty is num ? qty.toDouble() : double.tryParse(qty?.toString() ?? '');
    final unit = _arrivalUnitLabel(record['unit']?.toString());
    final price = record['unit_price'];
    final priceN = price is num ? price.toDouble() : double.tryParse(price?.toString() ?? '');
    final isDebt = record['is_debt'] == true;
    final supplier = (record['supplier_name'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A2438), Color(0xFF151D2E)]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: Text('№${record['arrival_id'] ?? '—'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
              ),
              Text(_fmtArrivalDate(record['arrival_date']), style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: _blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.inventory_2_outlined, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((record['product_name'] ?? '—').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    if (subline.isNotEmpty) Text(subline, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Пришло', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55))),
                      Text(qtyN != null ? '${formatRuInt(qtyN.round())} $unit' : '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Закупка', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55))),
                      Text(
                        priceN != null ? '${formatRuMoney(priceN, fractionDigits: 2)} ${record['currency'] ?? ''}' : '—',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF22C55E)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isDebt || supplier.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (isDebt)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: const Text('В долг', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                  ),
                if (supplier.isNotEmpty) Text(supplier, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ModalSheet extends StatelessWidget {
  const _ModalSheet({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppShape.sheetTop,
      ),
      padding: EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 14 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 36, height: 3, decoration: AppShape.sheetHandle(Colors.white.withValues(alpha: dark ? 0.14 : 0.22))),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.hint,
    required this.rows,
    required this.label,
    required this.onTap,
    required this.footerActionLabel,
    required this.onFooterAction,
    this.trailing,
  });

  final String title;
  final String hint;
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic> row) label;
  final void Function(Map<String, dynamic> row) onTap;
  final Widget Function(Map<String, dynamic> row)? trailing;
  final String footerActionLabel;
  final VoidCallback onFooterAction;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final s = q.trim().toLowerCase();
    final items = widget.rows.where((m) {
      if (s.isEmpty) return true;
      final text = widget.label(m).toLowerCase();
      return text.contains(s);
    }).take(250).toList();

    return _ModalSheet(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: widget.hint, isDense: true),
            onChanged: (v) => setState(() => q = v),
            autofocus: true,
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
              itemBuilder: (ctx, i) {
                final m = items[i];
                return ListTile(
                  dense: true,
                  title: Text(widget.label(m), style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
                  trailing: widget.trailing?.call(m) ?? const Icon(Icons.chevron_right_rounded),
                  onTap: () => widget.onTap(m),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onFooterAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(widget.footerActionLabel),
          ),
        ],
      ),
    );
  }
}

class _ArrivalRow {
  const _ArrivalRow({
    required this.quantity,
    required this.unit,
    required this.currency,
    required this.condition,
    required this.isDebt,
    this.productId,
    this.date,
    this.price,
    this.salePrice,
    this.barcode,
    this.supplierId,
  });

  final int? productId;
  final DateTime? date;
  final double quantity;
  final String unit;
  final double? price;
  final double? salePrice;
  final String? barcode;
  final String currency;
  final bool isDebt;
  final int? supplierId;
  final String condition; // new|used

  _ArrivalRow copyWith({
    int? productId,
    DateTime? date,
    double? quantity,
    String? unit,
    double? price,
    double? salePrice,
    String? barcode,
    String? currency,
    bool? isDebt,
    int? supplierId,
    String? condition,
  }) {
    return _ArrivalRow(
      productId: productId ?? this.productId,
      date: date ?? this.date,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      salePrice: salePrice ?? this.salePrice,
      barcode: barcode ?? this.barcode,
      currency: currency ?? this.currency,
      isDebt: isDebt ?? this.isDebt,
      supplierId: supplierId ?? this.supplierId,
      condition: condition ?? this.condition,
    );
  }
}

String _arrivalUnitLabel(String? unit) {
  const map = {
    'pcs': 'шт',
    'L': 'л',
    'kg': 'кг',
    'ml': 'мл',
    'g': 'г',
    'm': 'м',
    'pack': 'упак',
    'box': 'кор',
    'bottle': 'бут',
  };
  return map[unit] ?? unit ?? 'шт';
}

String _fmtDmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _fmtArrivalDate(dynamic v) {
  if (v == null) return '—';
  final raw = v.toString();
  final s = raw.length >= 10 ? raw.substring(0, 10) : raw;
  final parts = s.split('-');
  if (parts.length == 3) return '${parts[2]}.${parts[1]}.${parts[0]}';
  return s;
}

List<Map<String, dynamic>> _asListFromBody(String body) {
  final j = _tryJson(body);
  if (j is List) return j.cast<Map<String, dynamic>>();
  if (j is Map && j['results'] is List) return (j['results'] as List).cast<Map<String, dynamic>>();
  return const [];
}

List<Map<String, dynamic>> _asListOfMap(dynamic res) {
  try {
    // http.Response-like
    final status = (res as dynamic).statusCode as int?;
    final body = (res as dynamic).body as String?;
    if (status == 200 && body != null) return _asListFromBody(body);
  } catch (_) {}
  return const [];
}

dynamic _tryJson(String body) {
  try {
    return jsonDecode(body.isEmpty ? '{}' : body);
  } catch (_) {
    return {};
  }
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

String _fmtYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

