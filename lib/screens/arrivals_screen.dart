import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/session_controller.dart';
import '../services/api_client.dart';
import '../theme/app_shape.dart';
import '../utils/permissions.dart';
import '../widgets/app_scaffold.dart';

class ArrivalsScreen extends StatefulWidget {
  const ArrivalsScreen({super.key});

  @override
  State<ArrivalsScreen> createState() => _ArrivalsScreenState();
}

class _ArrivalsScreenState extends State<ArrivalsScreen> {
  bool loadingRefs = false;
  bool savingArrival = false;
  bool historyLoading = false;

  List<Map<String, dynamic>> products = const [];
  List<Map<String, dynamic>> suppliers = const [];
  List<Map<String, dynamic>> categories = const [];
  List<Map<String, dynamic>> warehouses = const [];

  int? productCategoryId;

  final List<_ArrivalRow> rows = <_ArrivalRow>[
    _ArrivalRow(
      quantity: 1,
      unit: 'pcs',
      currency: 'TJS',
      condition: 'new',
      isDebt: false,
    ),
  ];
  final TextEditingController commentCtrl = TextEditingController();

  // History
  DateTimeRange? historyRange;
  String historySearch = '';
  int? historyWarehouseId;
  List<Map<String, dynamic>> history = const [];

  Map<String, dynamic>? get _user => context.read<SessionController>().user;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRefs();
      await _loadHistory();
    });
  }

  @override
  void dispose() {
    commentCtrl.dispose();
    super.dispose();
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
        api.get('inventory/warehouses/'),
      ]);
      if (!mounted) return;

      products = _asListOfMap(res[0]);
      categories = _asListOfMap(res[1]);
      suppliers = _asListOfMap(res[2]);
      warehouses = _asListOfMap(res[3]);

      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        products = const [];
        categories = const [];
        suppliers = const [];
        warehouses = const [];
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
      if (historyWarehouseId != null) qp['warehouse'] = historyWarehouseId.toString();
      if (historyRange != null) {
        qp['date_from'] = _fmtYmd(historyRange!.start);
        qp['date_to'] = _fmtYmd(historyRange!.end);
      }
      if (historySearch.trim().isNotEmpty) qp['search'] = historySearch.trim();

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
          ..add(_ArrivalRow(quantity: 1, unit: 'pcs', currency: 'TJS', condition: 'new', isDebt: false));
        commentCtrl.text = '';
      });
      await _loadHistory();
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
        label: (m) => '${(m['name'] ?? '').toString()}${(m['model'] ?? '').toString().trim().isEmpty ? '' : ' ${(m['model'] ?? '').toString()}'} — ${(m['sku'] ?? '').toString()}',
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
              TextField(controller: phoneCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Телефон')),
              const SizedBox(height: 10),
              TextField(controller: noteCtrl, decoration: const InputDecoration(isDense: true, labelText: 'Заметка')),
              const SizedBox(height: 14),
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
      if (!mounted) return;
      final api = context.read<ApiClient>();
      final res = await api.post(
        'inventory/suppliers/',
        body: {'name': name, 'phone': phoneCtrl.text.trim(), 'note': noteCtrl.text.trim()},
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
                const SizedBox(height: 14),
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

    final warehouseName = (u['warehouse_name'] ?? '').toString().trim();
    final warehouseAddress = (u['warehouse_address'] ?? '').toString().trim();
    final hasWarehouse = (_asInt(u['warehouse']) ?? _asInt(u['warehouse_id'])) != null && warehouseName.isNotEmpty;

    return AppScaffold(
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRefs();
            await _loadHistory();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              Text('Поступление товаров', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 12),
              _Card(
                title: 'Ввод',
                subtitle: hasWarehouse
                    ? 'Склад — ${warehouseAddress.isEmpty ? warehouseName : '$warehouseName, $warehouseAddress'}'
                    : 'Введите название и адрес склада в профиле, чтобы они подставлялись здесь автоматически.',
                child: Column(
                  children: [
                    if (loadingRefs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                            const SizedBox(width: 10),
                            Text('Загрузка справочников…', style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    for (var i = 0; i < rows.length; i++)
                      _ArrivalRowCard(
                        index: i,
                        dark: dark,
                        cs: cs,
                        row: rows[i],
                        products: products,
                        suppliers: suppliers,
                        onPickProduct: () => _openProductPicker(i),
                        onPickSupplier: () => _openSupplierPicker(i),
                        onChanged: (next) => setState(() => rows[i] = next),
                        onDelete: rows.length <= 1 ? null : () => setState(() => rows.removeAt(i)),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => rows.add(_ArrivalRow(quantity: 1, unit: 'pcs', currency: 'TJS', condition: 'new', isDebt: false))),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить строку'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commentCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(isDense: true, labelText: 'Комментарий', hintText: 'Например: приход от поставщика X'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: savingArrival ? null : _saveArrival,
                      child: Text(savingArrival ? 'Сохранение…' : 'Сохранить поступление'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Card(
                title: 'История поступлений',
                subtitle: null,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'Поиск по товару или поставщику'),
                            onChanged: (v) => historySearch = v,
                            onSubmitted: (_) => _loadHistory(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Фильтры',
                          onPressed: () => _openHistoryFilters(),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                        IconButton(
                          tooltip: 'Обновить',
                          onPressed: _loadHistory,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (historyLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                            const SizedBox(width: 10),
                            Text('Загрузка…', style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )
                    else
                      _HistoryTable(dark: dark, cs: cs, rows: history),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openHistoryFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HistoryFilterSheet(
        warehouses: warehouses,
        warehouseId: historyWarehouseId,
        range: historyRange,
        onApply: (w, r) {
          setState(() {
            historyWarehouseId = w;
            historyRange = r;
          });
          _loadHistory();
        },
      ),
    );
  }
}

class _ArrivalRowCard extends StatelessWidget {
  const _ArrivalRowCard({
    required this.index,
    required this.dark,
    required this.cs,
    required this.row,
    required this.products,
    required this.suppliers,
    required this.onPickProduct,
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
  final VoidCallback onPickProduct;
  final VoidCallback onPickSupplier;
  final ValueChanged<_ArrivalRow> onChanged;
  final VoidCallback? onDelete;

  String _productLabel() {
    final pid = row.productId;
    if (pid == null) return 'Имя / модель / артикул';
    final p = products.firstWhere((x) => _asInt(x['id']) == pid, orElse: () => const {});
    final name = (p['name'] ?? '—').toString();
    final model = (p['model'] ?? '').toString().trim();
    final sku = (p['sku'] ?? '').toString().trim();
    return '$name${model.isEmpty ? '' : ' $model'} — $sku';
  }

  String _supplierLabel() {
    final sid = row.supplierId;
    if (sid == null) return 'Выберите поставщика';
    final s = suppliers.firstWhere((x) => _asInt(x['id']) == sid, orElse: () => const {});
    return (s['name'] ?? '—').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        color: dark ? const Color(0xFF253245) : const Color(0xFFF8FAFC),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: AppShape.br,
                  color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                  border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.08)),
                ),
                child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Text('Строка поступления', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
              const Spacer(),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  tooltip: 'Удалить строку',
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPickProduct,
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Align(alignment: Alignment.centerLeft, child: Text(_productLabel(), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: row.date ?? DateTime.now(),
              );
              if (picked != null) onChanged(row.copyWith(date: picked));
            },
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(row.date == null ? 'Выберите дату' : _fmtYmd(row.date!), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true, labelText: 'Кол-во'),
                  onChanged: (v) => onChanged(row.copyWith(quantity: double.tryParse(v.replaceAll(',', '.')) ?? row.quantity)),
                  controller: TextEditingController(text: row.quantity.toStringAsFixed(row.quantity % 1 == 0 ? 0 : 3)),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>(row.unit),
                  initialValue: row.unit,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, labelText: 'Ед.'),
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
                  onChanged: (v) => onChanged(row.copyWith(unit: v ?? 'pcs')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true, labelText: 'Цена закупки'),
                  onChanged: (v) => onChanged(row.copyWith(price: double.tryParse(v.replaceAll(',', '.')))),
                  controller: TextEditingController(text: (row.price ?? 0).toStringAsFixed(2)),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>(row.currency),
                  initialValue: row.currency,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, labelText: 'Валюта'),
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('\$')),
                    DropdownMenuItem(value: 'TJS', child: Text('с.')),
                  ],
                  onChanged: (v) => onChanged(row.copyWith(currency: v ?? 'USD')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: row.isDebt,
            onChanged: (v) => onChanged(row.copyWith(isDebt: v, supplierId: v ? row.supplierId : null)),
            title: const Text('В долг'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (row.isDebt) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: onPickSupplier,
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: Align(alignment: Alignment.centerLeft, child: Text(_supplierLabel(), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ),
          ],
          const SizedBox(height: 10),
          Text('Состояние', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'new', label: Text('Новый')),
              ButtonSegment(value: 'used', label: Text('Б/У')),
            ],
            selected: {row.condition},
            onSelectionChanged: (s) => onChanged(row.copyWith(condition: s.first)),
          ),
        ],
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.dark, required this.cs, required this.rows});
  final bool dark;
  final ColorScheme cs;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text('Нет записей.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface, fontSize: 12),
        dataTextStyle: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 12),
        columns: const [
          DataColumn(label: Text('Создано')),
          DataColumn(label: Text('Склад')),
          DataColumn(label: Text('№')),
          DataColumn(label: Text('Дата')),
          DataColumn(label: Text('Товар')),
          DataColumn(label: Text('Кол-во')),
          DataColumn(label: Text('Цена')),
          DataColumn(label: Text('Поставщик')),
          DataColumn(label: Text('В долг')),
        ],
        rows: rows.take(25).map((r) {
          final created = (r['created_at'] ?? '').toString().replaceFirst('T', ' ');
          final createdShort = created.isEmpty ? '—' : created.substring(0, created.length.clamp(0, 19));
          final wh = (r['warehouse_name'] ?? '—').toString();
          final arrivalId = (r['arrival_id'] ?? '—').toString();
          final date = (r['arrival_date'] ?? '').toString();
          final prod = (r['product_name'] ?? '—').toString();
          final q = r['quantity'];
          final unit = (r['unit'] ?? '').toString();
          final qty = q == null ? '—' : '${q.toString()} ${unit == 'pcs' ? 'шт' : unit}';
          final price = r['unit_price'] == null ? '—' : '${r['unit_price']} ${r['currency'] ?? ''}';
          final sup = (r['supplier_name'] ?? '—').toString();
          final debt = (r['is_debt'] == true) ? 'Да' : '—';
          return DataRow(
            cells: [
              DataCell(Text(createdShort)),
              DataCell(Text(wh)),
              DataCell(Text(arrivalId)),
              DataCell(Text(date.isEmpty ? '—' : date.substring(0, date.length.clamp(0, 10)))),
              DataCell(SizedBox(width: 260, child: Text(prod, overflow: TextOverflow.ellipsis))),
              DataCell(Text(qty)),
              DataCell(Text(price)),
              DataCell(SizedBox(width: 180, child: Text(sup, overflow: TextOverflow.ellipsis))),
              DataCell(Text(debt)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _HistoryFilterSheet extends StatefulWidget {
  const _HistoryFilterSheet({required this.warehouses, required this.warehouseId, required this.range, required this.onApply});
  final List<Map<String, dynamic>> warehouses;
  final int? warehouseId;
  final DateTimeRange? range;
  final void Function(int? warehouseId, DateTimeRange? range) onApply;

  @override
  State<_HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<_HistoryFilterSheet> {
  int? warehouseId;
  DateTimeRange? range;

  @override
  void initState() {
    super.initState();
    warehouseId = widget.warehouseId;
    range = widget.range;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _ModalSheet(
      title: 'Фильтры истории',
      child: Column(
        children: [
          DropdownButtonFormField<int>(
            key: ValueKey<int?>(warehouseId),
            initialValue: warehouseId,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Склад (все)'),
            items: [
              const DropdownMenuItem<int>(value: null, child: Text('Все склады')),
              ...widget.warehouses.map((w) {
                final id = _asInt(w['id']);
                return DropdownMenuItem<int>(value: id, child: Text((w['name'] ?? '—').toString()));
              }),
            ],
            onChanged: (v) => setState(() => warehouseId = v),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: range,
              );
              if (picked != null) setState(() => range = picked);
            },
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(range == null ? 'Дата от — Дата до' : '${_fmtYmd(range!.start)} — ${_fmtYmd(range!.end)}'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onApply(warehouseId, range);
                  },
                  child: const Text('Применить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(foregroundColor: dark ? Colors.white : null),
                  child: const Text('Отмена'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppShape.br,
        color: dark ? const Color(0xFF334155) : Colors.white,
        border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cs.onSurface)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
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
        color: dark ? const Color(0xFF0B1220) : Colors.white,
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
            const SizedBox(height: 12),
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
    this.supplierId,
  });

  final int? productId;
  final DateTime? date;
  final double quantity;
  final String unit;
  final double? price;
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
      currency: currency ?? this.currency,
      isDebt: isDebt ?? this.isDebt,
      supplierId: supplierId ?? this.supplierId,
      condition: condition ?? this.condition,
    );
  }
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

