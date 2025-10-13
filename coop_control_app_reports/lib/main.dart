// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as ex;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const CoopApp());

final currency = NumberFormat.currency(locale: 'es_GT', symbol: 'Q ');
final dateFmt = DateFormat('yyyy-MM-dd');

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// =====================
/// Catálogo y Receta
/// =====================

const List<String> catalogoProductos = [
  'LIMON',
  'LATA DE MAIZ',
  'CHAMOY',
  'SALSA VALENTINA',
  'QUESO CHEDAR',
  'DORITOS JALAPEÑOS',
  'TAJIN',
  'QUEZO MOZARELLA',
  'MAYONESSA',
];

/// Consumo POR PORCIÓN (misma unidad con la que manejas inventario)
final Map<String, double> recetaPorcion = {
  _norm('LIMON'): 0.5,
  _norm('LATA DE MAIZ'): 0.5,
  _norm('CHAMOY'): 0.01,
  _norm('SALSA VALENTINA'): 0.0142857,
  _norm('QUESO CHEDAR'): 0.083,
  _norm('DORITOS JALAPEÑOS'): 1.0,
  _norm('TAJIN'): 0.00875,
  _norm('QUEZO MOZARELLA'): 0.10,
  _norm('MAYONESSA'): 0.0833333,
};

/// Costos estándar por porción
const double COSTO_MP = 15.41; // materia prima
const double COSTO_MO = 3.57; // mano de obra
const double COSTO_GI = 1.67; // gastos indirectos
const double COSTO_TOTAL_STD = COSTO_MP + COSTO_MO + COSTO_GI; // 20.65

/// =====================
/// APP
/// =====================

class CoopApp extends StatelessWidget {
  const CoopApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Cooperativa',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cards = <_NavCard>[
      _NavCard(
        title: 'Inventarios',
        subtitle: 'Artículos, precio y existencia',
        icon: Icons.inventory_2_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InventoryScreen()),
        ),
      ),
      _NavCard(
        title: 'Compras',
        subtitle: 'Entradas al inventario (egresos en caja)',
        icon: Icons.shopping_cart_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PurchaseScreen()),
        ),
      ),
      _NavCard(
        title: 'Ventas',
        subtitle: 'Porciones vendidas (descuenta receta)',
        icon: Icons.point_of_sale_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SalesScreen()),
        ),
      ),
      _NavCard(
        title: 'Caja',
        subtitle: 'Ingresos, egresos y arqueo',
        icon: Icons.account_balance_wallet_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CashScreen()),
        ),
      ),
      _NavCard(
        title: 'Reporte de Costos',
        subtitle: 'Ingresos, costos y ganancia neta',
        icon: Icons.bar_chart,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CostReportScreen()),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Control Cooperativa')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (_, i) => cards[i],
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: cards.length,
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _NavCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// =====================
/// MODELOS + REPOS
/// =====================

class InventoryItem {
  final String id;
  final String nombre;
  final String unidad;
  final double precioCompra;
  final double cantidad; // existencia

  const InventoryItem({
    required this.id,
    required this.nombre,
    required this.unidad,
    required this.precioCompra,
    required this.cantidad,
  });

  double get valorExistencia => precioCompra * cantidad;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'unidad': unidad,
        'precioCompra': precioCompra,
        'cantidad': cantidad,
      };

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id'],
        nombre: j['nombre'],
        unidad: j['unidad'],
        precioCompra: (j['precioCompra'] as num).toDouble(),
        cantidad: (j['cantidad'] as num).toDouble(),
      );
}

class InventoryRepo {
  static const _key = 'inv_items_v1';

  Future<List<InventoryItem>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(InventoryItem.fromJson).toList();
  }

  Future<void> save(List<InventoryItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  int _indexByName(List<InventoryItem> items, String nombre) {
    final n = _norm(nombre);
    for (int i = 0; i < items.length; i++) {
      if (_norm(items[i].nombre) == n) return i;
    }
    return -1;
  }

  /// Entrada por compra (crea si no existe)
  Future<void> entradaCompra({
    required String nombre,
    required double unidades,
    required double precioUnitario,
    String unidad = 'unidad',
  }) async {
    final items = await load();
    final idx = _indexByName(items, nombre);
    if (idx >= 0) {
      final it = items[idx];
      items[idx] = InventoryItem(
        id: it.id,
        nombre: it.nombre,
        unidad: it.unidad,
        precioCompra: precioUnitario, // guarda último precio
        cantidad: it.cantidad + unidades,
      );
    } else {
      items.add(InventoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nombre: nombre,
        unidad: unidad,
        precioCompra: precioUnitario,
        cantidad: unidades,
      ));
    }
    await save(items);
  }

  /// Resultado de aplicar receta
  class ApplyResult {
    final bool ok;
    final List<String> faltantes;
    const ApplyResult(this.ok, this.faltantes);
  }

  /// Descuenta inventario con la receta multiplicada por [porciones].
  Future<ApplyResult> aplicarReceta(
      Map<String, double> receta, double porciones) async {
    final items = await load();
    final byName = {
      for (var i = 0; i < items.length; i++) _norm(items[i].nombre): i
    };
    final faltantes = <String>[];

    receta.forEach((k, v) {
      final need = v * porciones;
      final idx = byName[k];
      if (idx == null) {
        faltantes.add('$k (no encontrado)');
      } else if (items[idx].cantidad < need) {
        faltantes.add(
            '${items[idx].nombre}: falta ${(need - items[idx].cantidad).toStringAsFixed(3)}');
      }
    });

    if (faltantes.isNotEmpty) {
      return ApplyResult(false, List<String>.from(faltantes));
    }

    // Descontar
    receta.forEach((k, v) {
      final need = v * porciones;
      final idx = byName[k]!;
      final it = items[idx];
      items[idx] = InventoryItem(
        id: it.id,
        nombre: it.nombre,
        unidad: it.unidad,
        precioCompra: it.precioCompra,
        cantidad: (it.cantidad - need),
      );
    });
    await save(items);
    return const ApplyResult(true, <String>[]);
  }
}

class Purchase {
  final String id;
  final String fecha; // yyyy-MM-dd
  final String producto; // del catálogo
  final double unidades;
  final double precioUnit;

  Purchase({
    required this.id,
    required this.fecha,
    required this.producto,
    required this.unidades,
    required this.precioUnit,
  });

  double get total => unidades * precioUnit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'producto': producto,
        'unidades': unidades,
        'precioUnit': precioUnit,
      };

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        id: j['id'],
        fecha: j['fecha'],
        producto: j['producto'],
        unidades: (j['unidades'] as num).toDouble(),
        precioUnit: (j['precioUnit'] as num).toDouble(),
      );
}

class PurchaseRepo {
  static const _key = 'compras_v1';

  Future<List<Purchase>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Purchase.fromJson).toList();
  }

  Future<void> save(List<Purchase> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }
}

class Sale {
  final String id;
  final String fecha; // yyyy-MM-dd
  final double porciones;
  final double precioUnit;
  final String nota;

  Sale({
    required this.id,
    required this.fecha,
    required this.porciones,
    required this.precioUnit,
    required this.nota,
  });

  double get monto => porciones * precioUnit;

  Map<String, dynamic> toJson() =>
      {'id': id, 'fecha': fecha, 'porciones': porciones, 'precioUnit': precioUnit, 'nota': nota};

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'],
        fecha: j['fecha'],
        porciones: (j['porciones'] as num).toDouble(),
        precioUnit: (j['precioUnit'] as num).toDouble(),
        nota: j['nota'] ?? '',
      );
}

class SalesRepo {
  static const _key = 'ventas_diarias_v2';
  Future<List<Sale>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Sale.fromJson).toList();
  }

  Future<void> save(List<Sale> sales) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(sales.map((e) => e.toJson()).toList()));
  }
}

class CashMove {
  final String id;
  final String fecha; // yyyy-MM-dd
  final String tipo; // Ingreso/Egreso
  final String concepto;
  final double monto;

  CashMove(
      {required this.id,
      required this.fecha,
      required this.tipo,
      required this.concepto,
      required this.monto});

  Map<String, dynamic> toJson() =>
      {'id': id, 'fecha': fecha, 'tipo': tipo, 'concepto': concepto, 'monto': monto};

  factory CashMove.fromJson(Map<String, dynamic> j) => CashMove(
      id: j['id'],
      fecha: j['fecha'],
      tipo: j['tipo'],
      concepto: j['concepto'],
      monto: (j['monto'] as num).toDouble());
}

class CashCount {
  final String id;
  final String fecha; // yyyy-MM-dd
  final Map<String, int> denom; // '200' -> unidades

  CashCount({required this.id, required this.fecha, required this.denom});

  double get total =>
      200 * (denom['200'] ?? 0) +
      100 * (denom['100'] ?? 0) +
      50 * (denom['50'] ?? 0) +
      20 * (denom['20'] ?? 0) +
      10 * (denom['10'] ?? 0) +
      5 * (denom['5'] ?? 0) +
      1 * (denom['1'] ?? 0) +
      0.50 * (denom['0.50'] ?? 0) +
      0.25 * (denom['0.25'] ?? 0);

  Map<String, dynamic> toJson() => {'id': id, 'fecha': fecha, 'denom': denom};

  factory CashCount.fromJson(Map<String, dynamic> j) => CashCount(
      id: j['id'],
      fecha: j['fecha'],
      denom: (j['denom'] as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
}

class CashRepo {
  static const _mk = 'caja_movs_v1', _ck = 'caja_counts_v1';

  Future<List<CashMove>> loadMoves() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_mk);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(CashMove.fromJson).toList();
  }

  Future<void> saveMoves(List<CashMove> m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_mk, jsonEncode(m.map((e) => e.toJson()).toList()));
  }

  Future<List<CashCount>> loadCounts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_ck);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(CashCount.fromJson).toList();
  }

  Future<void> saveCounts(List<CashCount> c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_ck, jsonEncode(c.map((e) => e.toJson()).toList()));
  }
}

/// =====================
/// INVENTARIO UI
/// =====================

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final repo = InventoryRepo();
  List<InventoryItem> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    items = await repo.load();
    setState(() {});
  }

  Future<void> _addOrEdit({InventoryItem? item}) async {
    final res =
        await showDialog<InventoryItem>(context: context, builder: (_) => _ItemDialog(item: item));
    if (res != null) {
      final i = items.indexWhere((e) => e.id == res.id);
      if (i >= 0) {
        items[i] = res;
      } else {
        items.add(res);
      }
      await repo.save(items);
      setState(() {});
    }
  }

  Future<void> _ajustar(InventoryItem it) async {
    final c = TextEditingController();
    String t = 'Entrada';
    final q = await showDialog<double>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Movimiento de existencia'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                      value: t,
                      items: const [
                        DropdownMenuItem(value: 'Entrada', child: Text('Entrada')),
                        DropdownMenuItem(value: 'Salida', child: Text('Salida')),
                      ],
                      onChanged: (v) => t = v ?? 'Entrada'),
                  const SizedBox(height: 8),
                  TextField(
                      controller: c,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Cantidad'))
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () {
                      final v = double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
                      Navigator.pop(context, t == 'Entrada' ? v : -v);
                    },
                    child: const Text('Aplicar'))
              ],
            ));
    if (q != null && q != 0) {
      final idx = items.indexWhere((e) => e.id == it.id);
      items[idx] = InventoryItem(
          id: it.id,
          nombre: it.nombre,
          unidad: it.unidad,
          precioCompra: it.precioCompra,
          cantidad: (it.cantidad + q).clamp(0, double.infinity));
      await repo.save(items);
      setState(() {});
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Artículo', 'Unidad', 'Precio compra', 'Existencia', 'Valor'];
    final data = items
        .map((e) => [
              e.nombre,
              e.unidad,
              currency.format(e.precioCompra),
              e.cantidad.toStringAsFixed(2),
              currency.format(e.valorExistencia)
            ])
        .toList();
    final total = items.fold<double>(0, (p, e) => p + e.valorExistencia);
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Inventarios', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Fecha: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
          pw.SizedBox(height: 8),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Valor total: ${currency.format(total)}')),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'inventarios.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['Inventarios'];
    sheet.appendRow(['Artículo', 'Unidad', 'Precio compra', 'Existencia', 'Valor']);
    for (final e in items) {
      sheet.appendRow([e.nombre, e.unidad, e.precioCompra, e.cantidad, e.valorExistencia]);
    }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/inventarios.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (p, e) => p + e.valorExistencia);
    return Scaffold(
      appBar: AppBar(title: const Text('Inventarios'), actions: [
        PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
                  PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
                ])
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addOrEdit(),
          icon: const Icon(Icons.add),
          label: const Text('Artículo')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Artículos: ${items.length}'),
              Text('Valor total: ${currency.format(total)}'),
            ])),
        Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Sin artículos registrados'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return ListTile(
                        title: Text(it.nombre),
                        subtitle: Text('Unidad: ${it.unidad} · Precio: ${currency.format(it.precioCompra)}'),
                        leading: CircleAvatar(child: Text(it.cantidad.toStringAsFixed(0))),
                        trailing: Text(
                          'Existencia: ${it.cantidad.toStringAsFixed(2)}\n${currency.format(it.valorExistencia)}',
                          textAlign: TextAlign.right,
                        ),
                        onTap: () => _addOrEdit(item: it),
                        onLongPress: () => _ajustar(it),
                      );
                    }))
      ]),
    );
  }
}

class _ItemDialog extends StatefulWidget {
  final InventoryItem? item;
  const _ItemDialog({this.item});
  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final TextEditingController nombre =
      TextEditingController(text: widget.item?.nombre ?? '');
  late final TextEditingController unidad =
      TextEditingController(text: widget.item?.unidad ?? 'unidad');
  late final TextEditingController precio =
      TextEditingController(text: widget.item?.precioCompra.toString() ?? '');
  late final TextEditingController cantidad =
      TextEditingController(text: widget.item?.cantidad.toString() ?? '0');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Nuevo artículo' : 'Editar artículo'),
      content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 8),
        TextField(controller: unidad, decoration: const InputDecoration(labelText: 'Unidad')),
        const SizedBox(height: 8),
        TextField(
            controller: precio,
            decoration: const InputDecoration(labelText: 'Precio de compra'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 8),
        TextField(
            controller: cantidad,
            decoration: const InputDecoration(labelText: 'Existencia'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final it = InventoryItem(
                id: widget.item?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                nombre: nombre.text.trim(),
                unidad: unidad.text.trim(),
                precioCompra: double.tryParse(precio.text.replaceAll(',', '.')) ?? 0.0,
                cantidad: double.tryParse(cantidad.text.replaceAll(',', '.')) ?? 0.0,
              );
              Navigator.pop(context, it);
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// =====================
/// COMPRAS UI
/// =====================

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final purchases = <Purchase>[];
  final pRepo = PurchaseRepo();
  final invRepo = InventoryRepo();
  final cashRepo = CashRepo();

  String producto = catalogoProductos.first;
  final unidadesCtrl = TextEditingController();
  final precioCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    purchases..clear()..addAll(await pRepo.load());
    setState(() {});
  }

  Future<void> _agregar() async {
    final hoy = dateFmt.format(DateTime.now());
    final unidades = double.tryParse(unidadesCtrl.text.replaceAll(',', '.')) ?? 0;
    final precioUnit = double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
    if (unidades <= 0 || precioUnit <= 0) return;

    final compra = Purchase(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fecha: hoy,
      producto: producto,
      unidades: unidades,
      precioUnit: precioUnit,
    );
    purchases.add(compra);
    await pRepo.save(purchases);

    // Actualizar inventario
    await invRepo.entradaCompra(
        nombre: producto, unidades: unidades, precioUnitario: precioUnit);

    // Registrar egreso en caja
    final mv = CashMove(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fecha: hoy,
        tipo: 'Egreso',
        concepto: 'Compra $producto',
        monto: compra.total);
    final moves = await cashRepo.loadMoves()..add(mv);
    await cashRepo.saveMoves(moves);

    unidadesCtrl.clear();
    precioCtrl.clear();
    setState(() {});
  }

  double get total {
    return purchases.fold<double>(0, (p, x) => p + x.total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: producto,
                    items: catalogoProductos
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setState(() => producto = v ?? catalogoProductos.first),
                    decoration: const InputDecoration(labelText: 'Producto'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: unidadesCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Unidades'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: precioCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Precio unitario'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _agregar, child: const Text('Agregar')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fecha (auto): ${dateFmt.format(DateTime.now())}'),
                Text('Total: ${currency.format(total)}'),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: purchases.isEmpty
                ? const Center(child: Text('Sin compras registradas'))
                : ListView.separated(
                    itemBuilder: (_, i) {
                      final c = purchases[purchases.length - 1 - i];
                      return ListTile(
                        title: Text('${c.producto} · ${c.unidades} u'),
                        subtitle: Text('Fecha: ${c.fecha} · P.Unit: ${currency.format(c.precioUnit)}'),
                        trailing: Text(currency.format(c.total)),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: purchases.length,
                  ),
          ),
        ],
      ),
    );
  }
}

/// =====================
/// VENTAS UI
/// =====================

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final repo = SalesRepo();
  final inv = InventoryRepo();
  final cash = CashRepo();
  List<Sale> sales = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    sales = await repo.load();
    setState(() {});
  }

  Map<String, double> get resumenPorDia {
    final m = <String, double>{};
    for (final s in sales) {
      m[s.fecha] = (m[s.fecha] ?? 0) + s.monto;
    }
    return m;
  }

  Future<void> _nuevaVenta() async {
    final hoy = dateFmt.format(DateTime.now());
    final res = await showDialog<Sale>(
        context: context, builder: (_) => const _SaleDialog());
    if (res == null) return;

    // Aplica receta
    final r = await inv.aplicarReceta(recetaPorcion, res.porciones);
    if (!r.ok) {
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Faltantes en inventario'),
                content: Text(r.faltantes.join('\n')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'))
                ],
              ));
      return;
    }

    // Guarda venta
    sales.add(res);
    await repo.save(sales);

    // Ingreso en caja
    final mv = CashMove(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fecha: hoy,
        tipo: 'Ingreso',
        concepto: 'Venta ${res.porciones.toStringAsFixed(0)} porciones',
        monto: res.monto);
    final moves = await cash.loadMoves()..add(mv);
    await cash.saveMoves(moves);

    setState(() {});
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Porciones', 'P.Unit', 'Monto', 'Notas'];
    final data = sales
        .map((s) =>
            [s.fecha, s.porciones.toStringAsFixed(0), currency.format(s.precioUnit), currency.format(s.monto), s.nota])
        .toList();
    final sum = sales.fold<double>(0, (p, s) => p + s.monto);
    final byDay = resumenPorDia.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Ventas', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Fecha: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Text('Acumulado: ${currency.format(sum)}'),
          pw.SizedBox(height: 8),
          pw.Text('Resumen por día:'),
          pw.Table.fromTextArray(
              headers: ['Día', 'Total'],
              data: byDay.map((e) => [e.key, currency.format(e.value)]).toList()),
          pw.SizedBox(height: 8),
          pw.Text('Detalle:'),
          pw.Table.fromTextArray(headers: headers, data: data),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'ventas.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Ventas'];
    s1.appendRow(['Fecha', 'Porciones', 'P.Unit', 'Monto', 'Notas']);
    for (final s in sales) {
      s1.appendRow([s.fecha, s.porciones, s.precioUnit, s.monto, s.nota]);
    }
    final s2 = excel['Resumen_por_dia']..appendRow(['Día', 'Total']);
    resumenPorDia.forEach((k, v) => s2.appendRow([k, v]));
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ventas.xlsx';
    final file = File(path)..writeAsBytesSync(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final sum = sales.fold<double>(0, (p, s) => p + s.monto);
    final grouped = resumenPorDia.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Ventas'), actions: [
        PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
                  PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
                ])
      ]),
      floatingActionButton:
          FloatingActionButton.extended(onPressed: _nuevaVenta, icon: const Icon(Icons.add), label: const Text('Venta')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Registros: ${sales.length}'),
              Text('Acumulado: ${currency.format(sum)}'),
            ])),
        const Divider(),
        Expanded(
          child: grouped.isEmpty
              ? const Center(child: Text('Sin ventas registradas'))
              : ListView.separated(
                  itemCount: grouped.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = grouped[i];
                    return ListTile(
                      title: Text(e.key),
                      trailing: Text(currency.format(e.value)),
                      onTap: () {
                        final det = sales.where((s) => s.fecha == e.key).toList();
                        showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            builder: (_) => ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    Text('Detalle del ${e.key}',
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    ...det.map((s) => ListTile(
                                          title: Text(
                                              '${s.porciones.toStringAsFixed(0)} porciones · ${currency.format(s.monto)}'),
                                          subtitle: Text('P.Unit: ${currency.format(s.precioUnit)}\n${s.nota}'),
                                          isThreeLine: true,
                                        ))
                                  ],
                                ));
                      },
                    );
                  }),
        ),
      ]),
    );
  }
}

class _SaleDialog extends StatefulWidget {
  const _SaleDialog();
  @override
  State<_SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<_SaleDialog> {
  final porciones = TextEditingController();
  final precioUnit = TextEditingController();
  final nota = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(
      title: const Text('Nueva venta'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Fecha: $hoy'),
        const SizedBox(height: 8),
        TextField(
            controller: porciones,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Porciones')),
        const SizedBox(height: 8),
        TextField(
            controller: precioUnit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio por porción')),
        const SizedBox(height: 8),
        TextField(controller: nota, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final s = Sale(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                fecha: hoy,
                porciones: double.tryParse(porciones.text.replaceAll(',', '.')) ?? 0.0,
                precioUnit: double.tryParse(precioUnit.text.replaceAll(',', '.')) ?? 0.0,
                nota: nota.text.trim(),
              );
              Navigator.pop(context, s);
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// =====================
/// CAJA UI
/// =====================

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});
  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final repo = CashRepo();
  List<CashMove> moves = [];
  List<CashCount> counts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    moves = await repo.loadMoves();
    counts = await repo.loadCounts();
    setState(() {});
  }

  double get saldoTeorico {
    final ing = moves.where((m) => m.tipo == 'Ingreso').fold<double>(0, (p, m) => p + m.monto);
    final egr = moves.where((m) => m.tipo == 'Egreso').fold<double>(0, (p, m) => p + m.monto);
    return ing - egr;
  }

  double? get ultimoArqueo {
    if (counts.isEmpty) return null;
    counts.sort((a, b) => b.fecha.compareTo(a.fecha));
    return counts.first.total;
  }

  Future<void> _addMove() async {
    final res = await showDialog<CashMove>(context: context, builder: (_) => const _MoveDialog());
    if (res != null) {
      moves.add(res);
      await repo.saveMoves(moves);
      setState(() {});
    }
  }

  Future<void> _addCount() async {
    final res = await showDialog<CashCount>(context: context, builder: (_) => const _CountDialog());
    if (res != null) {
      counts.add(res);
      await repo.saveCounts(counts);
      setState(() {});
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Tipo', 'Concepto', 'Monto'];
    final data = moves.map((m) => [m.fecha, m.tipo, m.concepto, currency.format(m.monto)]).toList();
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Caja', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Fecha: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
          pw.SizedBox(height: 8),
          pw.Text('Último arqueo: ${ultimoArqueo == null ? 'sin registro' : currency.format(ultimoArqueo!)}'),
          if (ultimoArqueo != null)
            pw.Text('Diferencia: ${currency.format(ultimoArqueo! - saldoTeorico)}'),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'caja.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Caja_Movimientos']..appendRow(['Fecha', 'Tipo', 'Concepto', 'Monto']);
    for (final m in moves) {
      s1.appendRow([m.fecha, m.tipo, m.concepto, m.monto]);
    }
    final s2 = excel['Caja_Arqueos']
      ..appendRow(['Fecha', 'Q200', 'Q100', 'Q50', 'Q20', 'Q10', 'Q5', 'Q1', 'Q0.50', 'Q0.25', 'Total']);
    for (final c in counts) {
      s2.appendRow([
        c.fecha,
        c.denom['200'] ?? 0,
        c.denom['100'] ?? 0,
        c.denom['50'] ?? 0,
        c.denom['20'] ?? 0,
        c.denom['10'] ?? 0,
        c.denom['5'] ?? 0,
        c.denom['1'] ?? 0,
        c.denom['0.50'] ?? 0,
        c.denom['0.25'] ?? 0,
        c.total
      ]);
    }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/caja.xlsx';
    final file = File(path)..writeAsBytesSync(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final dif = ultimoArqueo == null ? null : (ultimoArqueo! - saldoTeorico);
    return Scaffold(
      appBar: AppBar(title: const Text('Caja'), actions: [
        PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
                  PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
                ])
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.extended(
            heroTag: 'm1', onPressed: _addMove, icon: const Icon(Icons.swap_vert), label: const Text('Movimiento')),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
            heroTag: 'm2', onPressed: _addCount, icon: const Icon(Icons.calculate_outlined), label: const Text('Arqueo')),
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
              Text(ultimoArqueo == null ? 'Sin arqueo' : 'Último arqueo: ${currency.format(ultimoArqueo)}'),
            ])),
        if (dif != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Diferencia: ${currency.format(dif)}'))),
        const Divider(),
        Expanded(
            child: moves.isEmpty
                ? const Center(child: Text('Sin movimientos'))
                : ListView.separated(
                    itemCount: moves.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = moves[i];
                      return ListTile(
                        leading: Icon(m.tipo == 'Ingreso'
                            ? Icons.arrow_downward
                            : Icons.arrow_upward),
                        title: Text('${m.tipo} · ${currency.format(m.monto)}'),
                        subtitle: Text('${m.concepto}\n${m.fecha}'),
                        isThreeLine: true,
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              moves.removeAt(i);
                              await repo.saveMoves(moves);
                              setState(() {});
                            }),
                      );
                    }))
      ]),
    );
  }
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog();
  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  String tipo = 'Ingreso';
  final concepto = TextEditingController();
  final monto = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(
        title: const Text('Nuevo movimiento'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
              value: tipo,
              items: const [
                DropdownMenuItem(value: 'Ingreso', child: Text('Ingreso')),
                DropdownMenuItem(value: 'Egreso', child: Text('Egreso'))
              ],
              onChanged: (v) => setState(() => tipo = v ?? 'Ingreso'),
              decoration: const InputDecoration(labelText: 'Tipo')),
          const SizedBox(height: 8),
          TextField(controller: concepto, decoration: const InputDecoration(labelText: 'Concepto')),
          const SizedBox(height: 8),
          TextField(
              controller: monto,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                final mv = CashMove(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    fecha: hoy,
                    tipo: tipo,
                    concepto: concepto.text.trim(),
                    monto: double.tryParse(monto.text.replaceAll(',', '.')) ?? 0.0);
                Navigator.pop(context, mv);
              },
              child: const Text('Guardar'))
        ]);
  }
}

class _CountDialog extends StatefulWidget {
  const _CountDialog();
  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  final Map<String, TextEditingController> ctrl = {
    '200': TextEditingController(text: '0'),
    '100': TextEditingController(text: '0'),
    '50': TextEditingController(text: '0'),
    '20': TextEditingController(text: '0'),
    '10': TextEditingController(text: '0'),
    '5': TextEditingController(text: '0'),
    '1': TextEditingController(text: '0'),
    '0.50': TextEditingController(text: '0'),
    '0.25': TextEditingController(text: '0'),
  };

  double _calcTotal() {
    double t = 0;
    ctrl.forEach((k, v) {
      final c = int.tryParse(v.text) ?? 0;
      final val = double.parse(k);
      t += c * val;
    });
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return StatefulBuilder(builder: (context, setStateSB) {
      return AlertDialog(
          title: const Text('Arqueo de caja'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ctrl.keys
                    .map((k) => SizedBox(
                        width: 100,
                        child: TextField(
                            controller: ctrl[k],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: 'Q $k'),
                            onChanged: (_) => setStateSB(() {}))))
                    .toList()),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('Total contado: ${currency.format(_calcTotal())}')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  final denom = {for (final e in ctrl.entries) e.key: int.tryParse(e.value.text) ?? 0};
                  final cc = CashCount(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      fecha: hoy,
                      denom: denom);
                  Navigator.pop(context, cc);
                },
                child: const Text('Guardar'))
          ]);
    });
  }
}

/// =====================
/// REPORTE DE COSTOS
/// =====================

class CostReportScreen extends StatefulWidget {
  const CostReportScreen({super.key});
  @override
  State<CostReportScreen> createState() => _CostReportScreenState();
}

class _CostReportScreenState extends State<CostReportScreen> {
  final sRepo = SalesRepo();
  List<Sale> all = [];
  DateTime from = DateTime.now().subtract(const Duration(days: 6));
  DateTime to = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    all = await sRepo.load();
    setState(() {});
  }

  List<Sale> get filtered {
    return all.where((s) {
      final d = DateTime.parse(s.fecha);
      final a = DateTime(from.year, from.month, from.day);
      final b = DateTime(to.year, to.month, to.day, 23, 59, 59);
      return !d.isBefore(a) && !d.isAfter(b);
    }).toList();
  }

  double get porcionesTotal => filtered.fold<double>(0, (p, s) => p + s.porciones);
  double get ingresoTotal => filtered.fold<double>(0, (p, s) => p + s.monto);
  double get costoMP => porcionesTotal * COSTO_MP;
  double get costoMO => porcionesTotal * COSTO_MO;
  double get costoGI => porcionesTotal * COSTO_GI;
  double get costoTotal => porcionesTotal * COSTO_TOTAL_STD;
  double get gananciaNeta => ingresoTotal - costoTotal;

  Future<void> pickFrom() async {
    final d = await showDatePicker(
        context: context,
        initialDate: from,
        firstDate: DateTime(2023),
        lastDate: DateTime(2100));
    if (d != null) setState(() => from = d);
  }

  Future<void> pickTo() async {
    final d = await showDatePicker(
        context: context,
        initialDate: to,
        firstDate: DateTime(2023),
        lastDate: DateTime(2100));
    if (d != null) setState(() => to = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reporte de Costos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickFrom,
                  icon: const Icon(Icons.date_range),
                  label: Text('Desde: ${dateFmt.format(from)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickTo,
                  icon: const Icon(Icons.date_range),
                  label: Text('Hasta: ${dateFmt.format(to)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _kv('Porciones vendidas', porcionesTotal.toStringAsFixed(0)),
          _kv('Ingresos', currency.format(ingresoTotal)),
          const Divider(),
          _kv('Costo MP (Q 15.41 x porción)', currency.format(costoMP)),
          _kv('Mano de obra (Q 3.57 x porción)', currency.format(costoMO)),
          _kv('Gastos indirectos (Q 1.67 x porción)', currency.format(costoGI)),
          _kv('Costo total', currency.format(costoTotal)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: gananciaNeta >= 0 ? Colors.green.withOpacity(.12) : Colors.red.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _kv('GANANCIA NETA', currency.format(gananciaNeta), bold: true),
          ),
          const SizedBox(height: 12),
          const Text('Ventas del período', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...filtered.map((s) => ListTile(
                dense: true,
                title: Text('${s.fecha} · ${s.porciones.toStringAsFixed(0)} porciones'),
                subtitle: Text('P.Unit: ${currency.format(s.precioUnit)}  ·  Nota: ${s.nota}'),
                trailing: Text(currency.format(s.monto)),
              )),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
