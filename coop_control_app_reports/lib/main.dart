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
    .replaceAll('á','a').replaceAll('é','e').replaceAll('í','i')
    .replaceAll('ó','o').replaceAll('ú','u').replaceAll('ñ','n')
    .replaceAll(RegExp(r'\s+'), ' ').trim();

/// Catálogo fijo para evitar errores de escritura en compras.
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

/// Receta: consumo POR PORCIÓN (misma unidad que el inventario).
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
const double COSTO_MO = 3.57;  // mano de obra
const double COSTO_GI = 1.67;  // gastos indirectos
const double COSTO_TOTAL_STD = COSTO_MP + COSTO_MO + COSTO_GI; // 20.65

//======================================================================
// APP / HOME
//======================================================================

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
    return Scaffold(
      appBar: AppBar(title: const Text('Control: Inventario, Caja y Ventas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _NavCard(
              title: 'Inventarios',
              subtitle: 'Registro de artículos, precio de compra y existencia.',
              icon: Icons.inventory_2_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InventoryScreen()),
              ),
            ),
            _NavCard(
              title: 'Compras',
              subtitle: 'Entrada a inventario y egreso en caja.',
              icon: Icons.local_mall_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PurchasesScreen()),
              ),
            ),
            _NavCard(
              title: 'Caja',
              subtitle: 'Ingresos, egresos y arqueo con denominaciones.',
              icon: Icons.point_of_sale_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CashScreen()),
              ),
            ),
            _NavCard(
              title: 'Ventas diarias',
              subtitle: 'Registro, porciones y resumen por día.',
              icon: Icons.bar_chart,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SalesScreen()),
              ),
            ),
            _NavCard(
              title: 'Reportes',
              subtitle: 'Ingresos, egresos, porciones y ganancia neta.',
              icon: Icons.summarize_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _NavCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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

//======================================================================
// MODELOS Y REPOS
//======================================================================

class InventoryItem {
  final String id;
  final String nombre;
  final String unidad;
  final double precioCompra;
  final double cantidad;

  InventoryItem({
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
    await p.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  int _indexByName(List<InventoryItem> items, String nombre) {
    final n = _norm(nombre);
    for (int i = 0; i < items.length; i++) {
      if (_norm(items[i].nombre) == n) return i;
    }
    return -1;
  }

  /// Aumenta existencia por una compra. Crea el artículo si no existe.
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
        precioCompra: precioUnitario, // último precio
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

  /// Aplica receta * porciones y descuenta inventario. Devuelve faltantes si hay.
  Future<(bool, List<String>)> aplicarReceta(
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
    if (faltantes.isNotEmpty) return (false, faltantes);

    // descontar
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
    Future<(bool, List<String>)> aplicarReceta(
    Map<String,double> receta, double porciones) async {
  final items = await load();
  final byName = { for (var i = 0; i < items.length; i++) _norm(items[i].nombre) : i };
  final faltantes = <String>[];

  receta.forEach((k, v) {
    final need = v * porciones;
    final idx = byName[k];
    if (idx == null) {
      faltantes.add('$k (no encontrado)');
    } else if (items[idx].cantidad < need) {
      faltantes.add('${items[idx].nombre}: falta ${(need - items[idx].cantidad).toStringAsFixed(3)}');
    }
  });

  if (faltantes.isNotEmpty) return (false, List<String>.from(faltantes));

  // descontar
  receta.forEach((k, v) {
    final need = v * porciones;
    final idx = byName[k]!;
    final it = items[idx];
    items[idx] = InventoryItem(
      id: it.id, nombre: it.nombre, unidad: it.unidad,
      precioCompra: it.precioCompra, cantidad: (it.cantidad - need),
    );
  });
  await save(items);
  return (true, <String>[]);
}

  }
}

class Purchase {
  final String id;
  final String fecha; // yyyy-MM-dd (hoy, no editable)
  final String producto; // del catálogo
  final double unidades;
  final double precioUnit;
  double get total => unidades * precioUnit;

  Purchase({
    required this.id,
    required this.fecha,
    required this.producto,
    required this.unidades,
    required this.precioUnit,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'producto': producto,
        'unidades': unidades,
        'precioUnit': precioUnit
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

class CashMove {
  final String id;
  final String fecha;
  final String tipo; // Ingreso / Egreso
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
  final String fecha;
  final Map<String, int> denom;
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
      0.25 * (denom['0.25'] ?? 0) +
      0.10 * (denom['0.10'] ?? 0) +
      0.05 * (denom['0.05'] ?? 0);
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

class Sale {
  final String id;
  final String fecha;
  final double monto;
  final String nota;
  final double porciones; // NUEVO

  Sale(
      {required this.id,
      required this.fecha,
      required this.monto,
      required this.nota,
      this.porciones = 1.0});

  Map<String, dynamic> toJson() =>
      {'id': id, 'fecha': fecha, 'monto': monto, 'nota': nota, 'porciones': porciones};

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
      id: j['id'],
      fecha: j['fecha'],
      monto: (j['monto'] as num).toDouble(),
      nota: j['nota'] ?? '',
      porciones: j['porciones'] == null
          ? 1.0
          : (j['porciones'] as num).toDouble());
}

class SalesRepo {
  static const _key = 'ventas_diarias_v1';
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

//======================================================================
// INVENTARIO
//======================================================================

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
    final res = await showDialog<InventoryItem>(
        context: context, builder: (_) => _ItemDialog(item: item));
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
              content: Column(mainAxisSize: MainAxisSize.min, children: [
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
                    decoration:
                        const InputDecoration(labelText: 'Cantidad'))
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () {
                      final v =
                          double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
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
          pw.Header(
              level: 0,
              child: pw.Text('Inventarios', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Fecha: ' + dateFmt.format(DateTime.now())),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
          pw.SizedBox(height: 8),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Valor total: ' + currency.format(total))),
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
                        subtitle: Text(
                            'Unidad: ${it.unidad} · Precio: ${currency.format(it.precioCompra)}'),
                        leading: CircleAvatar(child: Text(it.cantidad.toStringAsFixed(0))),
                        trailing: Text(
                            'Existencia: ${it.cantidad.toStringAsFixed(2)}\n${currency.format(it.valorExistencia)}',
                            textAlign: TextAlign.right),
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
                id: widget.item?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                nombre: nombre.text.trim(),
                unidad: unidad.text.trim(),
                precioCompra:
                    double.tryParse(precio.text.replaceAll(',', '.')) ?? 0.0,
                cantidad:
                    double.tryParse(cantidad.text.replaceAll(',', '.')) ?? 0.0,
              );
              Navigator.pop(context, it);
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

//======================================================================
// COMPRAS
//======================================================================

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final repo = PurchaseRepo();
  final inv = InventoryRepo();
  final cash = CashRepo();

  List<Purchase> compras = [];
  String producto = catalogoProductos.first;
  final unidades = TextEditingController();
  final precio = TextEditingController();
  final hoy = dateFmt.format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    compras = await repo.load();
    setState(() {});
  }

  Future<void> _addCompra() async {
    final u = double.tryParse(unidades.text.replaceAll(',', '.')) ?? 0;
    final pr = double.tryParse(precio.text.replaceAll(',', '.')) ?? 0;
    if (u <= 0 || pr <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Completa unidades y precio')));
      return;
    }

    final c = Purchase(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fecha: hoy,
      producto: producto,
      unidades: u,
      precioUnit: pr,
    );

    // 1) entrada a inventario
    await inv.entradaCompra(
        nombre: c.producto, unidades: c.unidades, precioUnitario: c.precioUnit);

    // 2) egreso en caja
    final mov = CashMove(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fecha: hoy,
      tipo: 'Egreso',
      concepto: 'Compra ${c.producto} (${c.unidades} x ${currency.format(c.precioUnit)})',
      monto: c.total,
    );
    final moves = await cash.loadMoves();
    moves.add(mov);
    await cash.saveMoves(moves);

    // 3) guardar compra
    compras.add(c);
    await repo.save(compras);
    setState(() {});
    unidades.clear();
    precio.clear();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Compra registrada')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras (entradas)')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
              enabled: false,
              decoration:
                  InputDecoration(labelText: 'Fecha', hintText: hoy),
            )),
            const SizedBox(width: 8),
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
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
              controller: unidades,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unidades compradas'),
            )),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
              controller: precio,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio unitario'),
            )),
          ]),
          const SizedBox(height: 8),
          Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                  onPressed: _addCompra,
                  icon: const Icon(Icons.save),
                  label: const Text('Registrar compra'))),
          const Divider(),
          Expanded(
              child: compras.isEmpty
                  ? const Center(child: Text('Sin compras'))
                  : ListView.separated(
                      itemCount: compras.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = compras[compras.length - 1 - i];
                        return ListTile(
                          title: Text(
                              '${c.producto}  ·  ${c.unidades} x ${currency.format(c.precioUnit)}'),
                          subtitle: Text(c.fecha),
                          trailing: Text(currency.format(c.total)),
                        );
                      }))
        ]),
      ),
    );
  }
}

//======================================================================
// CAJA
//======================================================================

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
    final ing =
        moves.where((m) => m.tipo == 'Ingreso').fold<double>(0, (p, m) => p + m.monto);
    final egr =
        moves.where((m) => m.tipo == 'Egreso').fold<double>(0, (p, m) => p + m.monto);
    return ing - egr;
  }

  double? get ultimoArqueo {
    if (counts.isEmpty) return null;
    counts.sort((a, b) => b.fecha.compareTo(a.fecha));
    return counts.first.total;
  }

  Future<void> _addMove() async {
    final res =
        await showDialog<CashMove>(context: context, builder: (_) => const _MoveDialog());
    if (res != null) {
      moves.add(res);
      await repo.saveMoves(moves);
      setState(() {});
    }
  }

  Future<void> _addCount() async {
    final res = await showDialog<CashCount>(
        context: context, builder: (_) => const _CountDialog());
    if (res != null) {
      counts.add(res);
      await repo.saveCounts(counts);
      setState(() {});
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Tipo', 'Concepto', 'Monto'];
    final data =
        moves.map((m) => [m.fecha, m.tipo, m.concepto, currency.format(m.monto)]).toList();
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Caja', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Fecha: ' + dateFmt.format(DateTime.now())),
          pw.SizedBox(height: 8),
          pw.Text('Saldo teórico: ' + currency.format(saldoTeorico)),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
          pw.SizedBox(height: 8),
          pw.Text('Último arqueo: ' +
              (ultimoArqueo == null ? 'sin registro' : currency.format(ultimoArqueo!))),
          if (ultimoArqueo != null)
            pw.Text('Diferencia: ' + currency.format(ultimoArqueo! - saldoTeorico)),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'caja.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Caja_Movimientos'];
    s1.appendRow(['Fecha', 'Tipo', 'Concepto', 'Monto']);
    for (final m in moves) {
      s1.appendRow([m.fecha, m.tipo, m.concepto, m.monto]);
    }
    final s2 = excel['Caja_Arqueos'];
    s2.appendRow(
        ['Fecha', 'Q200', 'Q100', 'Q50', 'Q20', 'Q10', 'Q5', 'Q1', 'Q0.50', 'Q0.25', 'Q0.10', 'Q0.05', 'Total']);
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
        c.denom['0.10'] ?? 0,
        c.denom['0.05'] ?? 0,
        c.total
      ]);
    }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/caja.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
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
            heroTag: 'm1',
            onPressed: _addMove,
            icon: const Icon(Icons.swap_vert),
            label: const Text('Movimiento')),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
            heroTag: 'm2',
            onPressed: _addCount,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Arqueo')),
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
              Text(ultimoArqueo == null
                  ? 'Sin arqueo'
                  : 'Último arqueo: ${currency.format(ultimoArqueo)}'),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    '0.10': TextEditingController(text: '0'),
    '0.05': TextEditingController(text: '0'),
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
                  final denom = {
                    for (final e in ctrl.entries) e.key: int.tryParse(e.value.text) ?? 0
                  };
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

//======================================================================
// VENTAS
//======================================================================

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final repo = SalesRepo();
  final invRepo = InventoryRepo(); // para descontar receta
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

  Map<String, double> get diarios {
    final m = <String, double>{};
    for (final s in sales) {
      m[s.fecha] = (m[s.fecha] ?? 0) + s.monto;
    }
    return m;
    }

  Future<void> _addSale() async {
    final res =
        await showDialog<Sale>(context: context, builder: (_) => const _SaleDialog());
    if (res != null) {
      // 1) descontar inventario según receta * porciones
      final (ok, falt) = await invRepo.aplicarReceta(recetaPorcion, res.porciones);
      if (!ok) {
        await showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('Stock insuficiente'),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: falt.map((f) => Text('• $f')).toList()),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Entendido'))
                  ],
                ));
        return;
      }

      // 2) guardar venta
      sales.add(res);
      await repo.save(sales);

      // 3) ingreso en caja
      final moves = await cash.loadMoves();
      moves.add(CashMove(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          fecha: res.fecha,
          tipo: 'Ingreso',
          concepto: 'Venta (${res.porciones.toStringAsFixed(2)} porciones)',
          monto: res.monto));
      await cash.saveMoves(moves);

      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Venta registrada y stock actualizado')));
      }
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Monto', 'Porciones', 'Notas'];
    final data = sales
        .map((s) => [s.fecha, currency.format(s.monto), s.porciones.toStringAsFixed(2), s.nota])
        .toList();
    final sum = sales.fold<double>(0, (p, s) => p + s.monto);
    final pors = sales.fold<double>(0, (p, s) => p + s.porciones);
    final byDay = diarios.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Ventas diarias', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Fecha: ' + dateFmt.format(DateTime.now())),
          pw.SizedBox(height: 8),
          pw.Text('Acumulado: ' + currency.format(sum) + ' · Porciones: ' + pors.toStringAsFixed(2)),
          pw.SizedBox(height: 8),
          pw.Text('Resumen por día:'),
          pw.Table.fromTextArray(
              headers: ['Día', 'Total'], data: byDay.map((e) => [e.key, currency.format(e.value)]).toList()),
          pw.SizedBox(height: 8),
          pw.Text('Detalle de ventas:'),
          pw.Table.fromTextArray(headers: headers, data: data),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'ventas.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Ventas'];
    s1.appendRow(['Fecha', 'Monto', 'Porciones', 'Notas']);
    for (final s in sales) {
      s1.appendRow([s.fecha, s.monto, s.porciones, s.nota]);
    }
    final s2 = excel['Resumen_por_dia'];
    s2.appendRow(['Día', 'Total']);
    diarios.forEach((k, v) => s2.appendRow([k, v]));
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ventas.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final sum = sales.fold<double>(0, (p, s) => p + s.monto);
    final grouped = diarios.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Ventas diarias'), actions: [
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
          FloatingActionButton.extended(onPressed: _addSale, icon: const Icon(Icons.add), label: const Text('Venta')),
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
                                              title: Text(currency.format(s.monto)),
                                              subtitle: Text('Porciones: ${s.porciones.toStringAsFixed(2)} · ${s.nota}'),
                                            )),
                                      ]));
                        },
                      );
                    }))
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
  final monto = TextEditingController();
  final porciones = TextEditingController(text: '1');
  final nota = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(
        title: const Text('Nueva venta'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto')),
          const SizedBox(height: 8),
          TextField(
              controller: porciones,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Porciones')),
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
                    monto: double.tryParse(monto.text.replaceAll(',', '.')) ?? 0.0,
                    nota: nota.text.trim(),
                    porciones: double.tryParse(porciones.text.replaceAll(',', '.')) ?? 1.0);
                Navigator.pop(context, s);
              },
              child: const Text('Guardar')),
        ]);
  }
}

//======================================================================
// REPORTES
//======================================================================

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final sales = SalesRepo();
  final compras = PurchaseRepo();
  final caja = CashRepo();

  DateTimeRange rango =
      DateTimeRange(start: DateTime.now(), end: DateTime.now());

  bool _inRange(String ymd) {
    final d = DateTime.parse(ymd);
    return !d.isBefore(DateTime(rango.start.year, rango.start.month, rango.start.day)) &&
        !d.isAfter(DateTime(rango.end.year, rango.end.month, rango.end.day, 23, 59, 59));
  }

  void _setHoy() {
    final h = DateTime.now();
    setState(() => rango =
        DateTimeRange(start: DateTime(h.year, h.month, h.day), end: DateTime(h.year, h.month, h.day)));
  }

  void _set7() {
    final h = DateTime.now();
    setState(() => rango = DateTimeRange(start: h.subtract(const Duration(days: 6)), end: h));
  }

  void _setMes() {
    final h = DateTime.now();
    setState(() => rango = DateTimeRange(start: DateTime(h.year, h.month, 1), end: h));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: FutureBuilder(
          future: Future.wait([sales.load(), compras.load(), caja.loadMoves()]),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<Sale> vs = snap.data![0] as List<Sale>;
            final List<Purchase> cs = snap.data![1] as List<Purchase>;
            final List<CashMove> ms = snap.data![2] as List<CashMove>;

            final ventasR = vs.where((v) => _inRange(v.fecha)).toList();
            final comprasR = cs.where((c) => _inRange(c.fecha)).toList();
            final ingresosVentas =
                ventasR.fold<double>(0, (p, v) => p + v.monto);
            final porcionesVendidas =
                ventasR.fold<double>(0, (p, v) => p + v.porciones);
            final egresosCompras =
                comprasR.fold<double>(0, (p, c) => p + c.total);
            final gananciaNeta =
                ingresosVentas - (porcionesVendidas * COSTO_TOTAL_STD);

            final otrosIng = ms
                .where((m) => _inRange(m.fecha) && m.tipo == 'Ingreso')
                .fold<double>(0, (p, m) => p + m.monto);
            final otrosEgr = ms
                .where((m) => _inRange(m.fecha) && m.tipo == 'Egreso')
                .fold<double>(0, (p, m) => p + m.monto);
            final saldoTeorico = ms
                .where((m) => _inRange(m.fecha))
                .fold<double>(0, (p, m) => p + (m.tipo == 'Ingreso' ? m.monto : -m.monto));

            return ListView(padding: const EdgeInsets.all(12), children: [
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: _setHoy, child: const Text('Hoy')),
                OutlinedButton(onPressed: _set7, child: const Text('Últimos 7 días')),
                OutlinedButton(onPressed: _setMes, child: const Text('Este mes')),
                OutlinedButton(
                    onPressed: () async {
                      final res = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDateRange: rango);
                      if (res != null) setState(() => rango = res);
                    },
                    child: const Text('Elegir rango')),
              ]),
              const SizedBox(height: 12),
              Text('Rango: ${dateFmt.format(rango.start)} → ${dateFmt.format(rango.end)}'),
              const SizedBox(height: 12),
              Card(
                  child: ListTile(
                title: const Text('Ingresos por ventas'),
                trailing: Text(currency.format(ingresosVentas),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle:
                    Text('Porciones vendidas: ${porcionesVendidas.toStringAsFixed(2)}'),
              )),
              Card(
                  child: ListTile(
                title: const Text('Egresos por compras'),
                trailing: Text(currency.format(egresosCompras),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
              Card(
                  child: ListTile(
                title: const Text('Ganancia neta (destacada)'),
                subtitle: Text(
                    'Costo estándar: ${currency.format(COSTO_TOTAL_STD)} x porción'),
                trailing: Text(currency.format(gananciaNeta),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: gananciaNeta >= 0 ? Colors.teal : Colors.red,
                        fontSize: 18)),
              )),
              const SizedBox(height: 8),
              Card(
                  child: ListTile(
                title: const Text('Otros movimientos de caja'),
                subtitle: Text(
                    'Ingresos: ${currency.format(otrosIng)} · Egresos: ${currency.format(otrosEgr)}'),
              )),
              Card(
                  child: ListTile(
                title: const Text('Saldo teórico de caja en el rango'),
                trailing: Text(currency.format(saldoTeorico),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]);
          }),
    );
  }
}
