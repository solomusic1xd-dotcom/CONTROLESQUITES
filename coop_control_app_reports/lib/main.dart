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

/// ===== Utilidades globales =====

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

/// Para Excel: convier­te una fila a strings simples (evita errores de tipos).
List<dynamic> xsRow(List<dynamic> row) => row.map((e) {
      if (e is num) return e.toString();
      if (e is DateTime) return dateFmt.format(e);
      return e?.toString() ?? '';
    }).toList();

/// ===== Catálogo y Receta =====

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

/// Consumo por porción (misma unidad que compras).
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

/// Costos estándar (por porción)
const double COSTO_MP_STD = 15.41; // *Solo referencia; el costo real usa PEPS*
const double COSTO_MO = 3.57;
const double COSTO_GI = 1.67;

/// ===== Arranque =====
void main() => runApp(const CoopApp());

class CoopApp extends StatelessWidget {
  const CoopApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CONTROL ESQUITES',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeScreen(),
    );
  }
}

/// ===== Home =====
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('CONTROL ESQUITES'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NavCard(
            title: 'Inventario (PEPS)',
            subtitle:
                'Existencias por producto. Valor al costo (lotes vigentes).',
            icon: Icons.inventory_2_outlined,
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const InventoryScreen())),
          ),
          _NavCard(
            title: 'Compras',
            subtitle: 'Ingresar lotes (fecha, cantidad, precio).',
            icon: Icons.shopping_cart_outlined,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const PurchaseScreen())),
          ),
          _NavCard(
            title: 'Ventas',
            subtitle:
                'Registra porciones vendidas. Aplica receta y descuenta PEPS.',
            icon: Icons.point_of_sale_outlined,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SalesScreen())),
          ),
          _NavCard(
            title: 'Caja',
            subtitle: 'Movimientos y arqueo con denominaciones.',
            icon: Icons.calculate_outlined,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CashScreen())),
          ),
          _NavCard(
            title: 'Reporte de Costos',
            subtitle:
                'Ingresos, costos (MP PEPS, MO, GI) y ganancia por rango.',
            icon: Icons.bar_chart_outlined,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CostReportScreen())),
          ),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final String title, subtitle;
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

/// ===== Datos: Compras (lotes) - base PEPS =====

class Purchase {
  final String id;
  final String fecha; // yyyy-MM-dd
  final String producto; // del catálogo
  final String unidad; // texto libre (ej. gr, ml, unidad)
  final double unidades; // cantidad comprada
  final double precioUnit; // costo por unidad
  double restante; // saldo pendiente (para PEPS)

  Purchase({
    required this.id,
    required this.fecha,
    required this.producto,
    required this.unidad,
    required this.unidades,
    required this.precioUnit,
    required this.restante,
  });

  double get total => unidades * precioUnit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'producto': producto,
        'unidad': unidad,
        'unidades': unidades,
        'precioUnit': precioUnit,
        'restante': restante,
      };

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        id: j['id'],
        fecha: j['fecha'],
        producto: j['producto'],
        unidad: j['unidad'] ?? 'unidad',
        unidades: (j['unidades'] as num).toDouble(),
        precioUnit: (j['precioUnit'] as num).toDouble(),
        restante: (j['restante'] as num).toDouble(),
      );
}

class PurchaseRepo {
  static const _key = 'compras_v2';

  Future<List<Purchase>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Purchase.fromJson).toList();
  }

  Future<void> save(List<Purchase> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }

  /// Existencia total por producto (suma de "restante" en los lotes).
  Future<double> stockOf(String producto) async {
    final xs = await load();
    final n = _norm(producto);
    return xs
        .where((e) => _norm(e.producto) == n)
        .fold<double>(0, (p, e) => p + e.restante);
  }

  /// Costo y descuento de lotes según PEPS (devuelve costoMP).
  Future<PEPSResult> consumirPEPS(
      {required Map<String, double> receta,
      required double porciones}) async {
    final xs = await load();

    // 1) Validar faltantes
    final falt = <String>[];
    receta.forEach((prodN, porUnidad) {
      final need = (porUnidad * porciones);
      final disp = xs
          .where((e) => _norm(e.producto) == prodN)
          .fold<double>(0, (p, e) => p + e.restante);
      if (disp + 1e-9 < need) {
        falt.add('$prodN: falta ${(need - disp).toStringAsFixed(3)}');
      }
    });
    if (falt.isNotEmpty) {
      return PEPSResult(false, falt, 0.0);
    }

    // 2) Consumir PEPS
    double costo = 0.0;
    for (final entry in receta.entries) {
      final prodN = entry.key;
      double need = entry.value * porciones;

      // lotes por fecha (ascendente)
      final lots = xs
          .where((e) => _norm(e.producto) == prodN && e.restante > 0)
          .toList()
        ..sort((a, b) {
          final cmp = a.fecha.compareTo(b.fecha);
          if (cmp != 0) return cmp;
          return a.id.compareTo(b.id);
        });

      for (final lot in lots) {
        if (need <= 0) break;
        final take = need <= lot.restante ? need : lot.restante;
        costo += take * lot.precioUnit;
        lot.restante = (lot.restante - take);
        need -= take;
      }
    }

    await save(xs);
    return PEPSResult(true, const [], costo);
  }
}

class PEPSResult {
  final bool ok;
  final List<String> faltantes;
  final double costoMP;
  PEPSResult(this.ok, this.faltantes, this.costoMP);
}

/// ===== Datos: Ventas =====

class Sale {
  final String id;
  final String fecha; // yyyy-MM-dd
  final double porciones;
  final double precioUnit;

  // calculados y guardados
  final double ingreso;
  final double costoMP;
  final double costoMO;
  final double costoGI;
  final double costoTotal;
  final double ganancia;
  final String nota;

  Sale({
    required this.id,
    required this.fecha,
    required this.porciones,
    required this.precioUnit,
    required this.ingreso,
    required this.costoMP,
    required this.costoMO,
    required this.costoGI,
    required this.costoTotal,
    required this.ganancia,
    required this.nota,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'porciones': porciones,
        'precioUnit': precioUnit,
        'ingreso': ingreso,
        'costoMP': costoMP,
        'costoMO': costoMO,
        'costoGI': costoGI,
        'costoTotal': costoTotal,
        'ganancia': ganancia,
        'nota': nota,
      };

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'],
        fecha: j['fecha'],
        porciones: (j['porciones'] as num).toDouble(),
        precioUnit: (j['precioUnit'] as num).toDouble(),
        ingreso: (j['ingreso'] as num).toDouble(),
        costoMP: (j['costoMP'] as num).toDouble(),
        costoMO: (j['costoMO'] as num).toDouble(),
        costoGI: (j['costoGI'] as num).toDouble(),
        costoTotal: (j['costoTotal'] as num).toDouble(),
        ganancia: (j['ganancia'] as num).toDouble(),
        nota: j['nota'] ?? '',
      );
}

class SalesRepo {
  static const _key = 'ventas_v2';
  Future<List<Sale>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Sale.fromJson).toList();
  }

  Future<void> save(List<Sale> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }
}

/// ===== Datos: Caja =====

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
  final Map<String, int> denom; // '200','100',...,'0.25'
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

  Map<String, dynamic> toJson() =>
      {'id': id, 'fecha': fecha, 'denom': denom};
  factory CashCount.fromJson(Map<String, dynamic> j) => CashCount(
      id: j['id'],
      fecha: j['fecha'],
      denom: (j['denom'] as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
}

class CashRepo {
  static const _mk = 'caja_movs_v2', _ck = 'caja_counts_v2';

  Future<List<CashMove>> loadMoves() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_mk);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(CashMove.fromJson).toList();
  }

  Future<void> saveMoves(List<CashMove> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_mk, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }

  Future<List<CashCount>> loadCounts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_ck);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(CashCount.fromJson).toList();
  }

  Future<void> saveCounts(List<CashCount> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_ck, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }
}

/// ===== Pantalla: Compras =====

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final repo = PurchaseRepo();
  List<Purchase> lots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    lots = await repo.load();
    lots.sort((a, b) {
      final c = b.fecha.compareTo(a.fecha);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    setState(() {});
  }

  Future<void> _add() async {
    final res = await showDialog<Purchase>(
        context: context, builder: (_) => const _PurchaseDialog());
    if (res != null) {
      lots.add(res);
      await repo.save(lots);
      _load();
    }
  }

  Future<void> _delete(Purchase p) async {
    if (p.restante < p.unidades - 1e-9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se puede borrar: el lote ya tiene consumo.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar lote'),
        content:
            const Text('¿Eliminar definitivamente este registro de compra?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok ?? false) {
      lots.removeWhere((e) => e.id == p.id);
      await repo.save(lots);
      _load();
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = [
      'Fecha',
      'Producto',
      'Unidad',
      'Unidades',
      'Restante',
      'P.Unit',
      'Total'
    ];
    final data = lots
        .map((e) => [
              e.fecha,
              e.producto,
              e.unidad,
              e.unidades.toStringAsFixed(3),
              e.restante.toStringAsFixed(3),
              currency.format(e.precioUnit),
              currency.format(e.total)
            ])
        .toList();
    final sum = lots.fold<double>(0, (p, e) => p + e.total);
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Compras', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Generado: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
          pw.SizedBox(height: 8),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Total: ${currency.format(sum)}')),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'compras.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final sh = excel['Compras'];
    sh.appendRow(xsRow(['Fecha', 'Producto', 'Unidad', 'Unidades', 'Restante', 'P.Unit', 'Total']));
    for (final e in lots) {
      sh.appendRow(xsRow([
        e.fecha,
        e.producto,
        e.unidad,
        e.unidades,
        e.restante,
        e.precioUnit,
        e.total
      ]));
    }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/compras.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      floatingActionButton:
          FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Compra')),
      body: lots.isEmpty
          ? const Center(child: Text('Sin compras'))
          : ListView.separated(
              itemCount: lots.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = lots[i];
                return ListTile(
                  title: Text('${e.producto} · ${currency.format(e.precioUnit)}'),
                  subtitle: Text('${e.fecha}  ·  ${e.unidad}\n'
                      'Comprado: ${e.unidades.toStringAsFixed(3)}  ·  Restante: ${e.restante.toStringAsFixed(3)}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(e),
                  ),
                );
              }),
    );
  }
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog();
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  String prod = catalogoProductos.first;
  final unidad = TextEditingController(text: 'unidad');
  final unidades = TextEditingController();
  final precio = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(
      title: const Text('Nueva compra (lote)'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(enabled: false, decoration: InputDecoration(labelText: 'Fecha', hintText: hoy)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: prod,
            items: catalogoProductos
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => prod = v ?? prod),
            decoration: const InputDecoration(labelText: 'Producto'),
          ),
          const SizedBox(height: 8),
          TextField(controller: unidad, decoration: const InputDecoration(labelText: 'Unidad (gr, ml, unidad...)')),
          const SizedBox(height: 8),
          TextField(
              controller: unidades,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unidades')),
          const SizedBox(height: 8),
          TextField(
              controller: precio,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio por unidad')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final u = double.tryParse(unidades.text.replaceAll(',', '.')) ?? 0.0;
              final p = double.tryParse(precio.text.replaceAll(',', '.')) ?? 0.0;
              final lot = Purchase(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                fecha: hoy,
                producto: prod,
                unidad: unidad.text.trim().isEmpty ? 'unidad' : unidad.text.trim(),
                unidades: u,
                precioUnit: p,
                restante: u,
              );
              Navigator.pop(context, lot);
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// ===== Pantalla: Inventario (agregado por producto desde lotes) =====

class InventoryRow {
  final String producto;
  final String unidad;
  final double cantidad;
  final double precioPromedio; // ponderado por restante
  final double valor;

  InventoryRow(
      {required this.producto,
      required this.unidad,
      required this.cantidad,
      required this.precioPromedio,
      required this.valor});
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final repo = PurchaseRepo();
  List<InventoryRow> rows = [];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  Future<void> _rebuild() async {
    final lots = await repo.load();
    final Map<String, List<Purchase>> by = {};
    for (final l in lots) {
      by.putIfAbsent(_norm(l.producto), () => []).add(l);
    }

    final out = <InventoryRow>[];
    for (final entry in by.entries) {
      final prodN = entry.key;
      final items = entry.value;
      final nombreReal = items.last.producto; // cualquiera
      final unidad = items.last.unidad;
      final total = items.fold<double>(0, (p, e) => p + e.restante);
      if (total <= 0) continue;
      final valor = items.fold<double>(0, (p, e) => p + e.restante * e.precioUnit);
      final prom = valor / total;
      out.add(InventoryRow(
          producto: nombreReal,
          unidad: unidad,
          cantidad: total,
          precioPromedio: prom,
          valor: valor));
    }
    out.sort((a, b) => a.producto.compareTo(b.producto));
    rows = out;
    setState(() {});
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Producto', 'Unidad', 'Existencia', 'P.Prom', 'Valor'];
    final data = rows
        .map((r) => [
              r.producto,
              r.unidad,
              r.cantidad.toStringAsFixed(3),
              currency.format(r.precioPromedio),
              currency.format(r.valor)
            ])
        .toList();
    final sum = rows.fold<double>(0, (p, e) => p + e.valor);
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Inventario (PEPS)', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Generado: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
          pw.SizedBox(height: 8),
          pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Valor total: ${currency.format(sum)}')),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'inventario.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final sh = excel['Inventario'];
    sh.appendRow(xsRow(['Producto', 'Unidad', 'Existencia', 'P.Prom', 'Valor']));
    for (final r in rows) {
      sh.appendRow(xsRow([r.producto, r.unidad, r.cantidad, r.precioPromedio, r.valor]));
    }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/inventario.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final sum = rows.fold<double>(0, (p, e) => p + e.valor);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario (PEPS)'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Productos: ${rows.length}'),
              Text('Valor total: ${currency.format(sum)}'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No hay existencias'))
              : RefreshIndicator(
                  onRefresh: _rebuild,
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return ListTile(
                        title: Text(r.producto),
                        subtitle: Text('Unidad: ${r.unidad} · P.Prom: ${currency.format(r.precioPromedio)}'),
                        trailing: Text(
                            'Exist.: ${r.cantidad.toStringAsFixed(3)}\n${currency.format(r.valor)}',
                            textAlign: TextAlign.right),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

/// ===== Pantalla: Ventas =====

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final repo = SalesRepo();
  final purchaseRepo = PurchaseRepo();
  final cashRepo = CashRepo();

  List<Sale> sales = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    sales = await repo.load();
    sales.sort((a, b) => b.fecha.compareTo(a.fecha));
    setState(() {});
  }

  Future<void> _add() async {
    final res =
        await showDialog<_NewSale>(context: context, builder: (_) => const _SaleDialog());
    if (res == null) return;

    // Aplica receta con PEPS
    final recetaN = {for (final e in recetaPorcion.entries) e.key: e.value};
    final peps = await purchaseRepo
        .consumirPEPS(receta: recetaN, porciones: res.porciones);

    if (!peps.ok) {
      await showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Inventario insuficiente'),
                content: Text((peps.faltantes).join('\n')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Aceptar'))
                ],
              ));
      return;
    }

    final double ingreso = res.porciones * res.precioUnit;
    final double mo = res.porciones * COSTO_MO;
    final double gi = res.porciones * COSTO_GI;
    final double costoTotal = peps.costoMP + mo + gi;
    final double ganancia = ingreso - costoTotal;

    final sale = Sale(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fecha: dateFmt.format(DateTime.now()),
      porciones: res.porciones,
      precioUnit: res.precioUnit,
      ingreso: ingreso,
      costoMP: peps.costoMP,
      costoMO: mo,
      costoGI: gi,
      costoTotal: costoTotal,
      ganancia: ganancia,
      nota: res.nota ?? '',
    );

    sales.add(sale);
    await repo.save(sales);

    // Registrar ingreso a caja
    final mv = CashMove(
        id: sale.id,
        fecha: sale.fecha,
        tipo: 'Ingreso',
        concepto: 'Ventas · ${sale.porciones.toStringAsFixed(0)} porciones',
        monto: ingreso);
    final moves = await cashRepo.loadMoves()..add(mv);
    await cashRepo.saveMoves(moves);

    _load();
  }

  Map<String, double> get diarios {
    final m = <String, double>{};
    for (final s in sales) {
      m[s.fecha] = (m[s.fecha] ?? 0) + s.ingreso;
    }
    return m;
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Porciones', 'P.Unit', 'Ingreso', 'MP(PEPS)', 'MO', 'GI', 'Costo', 'Ganancia', 'Nota'];
    final data = sales
        .map((s) => [
              s.fecha,
              s.porciones.toStringAsFixed(0),
              currency.format(s.precioUnit),
              currency.format(s.ingreso),
              currency.format(s.costoMP),
              currency.format(s.costoMO),
              currency.format(s.costoGI),
              currency.format(s.costoTotal),
              currency.format(s.ganancia),
              s.nota
            ])
        .toList();
    final sum = sales.fold<double>(0, (p, e) => p + e.ingreso);
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Ventas', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Generado: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Text('Acumulado ingresos: ${currency.format(sum)}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'ventas.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Ventas'];
    s1.appendRow(xsRow(
        ['Fecha', 'Porciones', 'P.Unit', 'Ingreso', 'MP(PEPS)', 'MO', 'GI', 'Costo', 'Ganancia', 'Nota']));
    for (final s in sales) {
      s1.appendRow(xsRow([
        s.fecha,
        s.porciones,
        s.precioUnit,
        s.ingreso,
        s.costoMP,
        s.costoMO,
        s.costoGI,
        s.costoTotal,
        s.ganancia,
        s.nota
      ]));
    }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ventas.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final sum = sales.fold<double>(0, (p, e) => p + e.ingreso);
    final grouped = diarios.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _add, icon: const Icon(Icons.add), label: const Text('Venta')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Registros: ${sales.length}'),
                Text('Ingresos: ${currency.format(sum)}'),
              ]),
        ),
        const Divider(height: 1),
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
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    ...det.map((s) => ListTile(
                                          title: Text(
                                              '${s.porciones.toStringAsFixed(0)} porciones · ${currency.format(s.ingreso)}'),
                                          subtitle: Text(
                                              'MP: ${currency.format(s.costoMP)}  ·  MO: ${currency.format(s.costoMO)}  ·  GI: ${currency.format(s.costoGI)}\n'
                                              'Ganancia: ${currency.format(s.ganancia)}${s.nota.isEmpty ? '' : '\n${s.nota}'}'),
                                        )),
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

class _NewSale {
  final double porciones;
  final double precioUnit;
  final String? nota;
  _NewSale(this.porciones, this.precioUnit, this.nota);
}

class _SaleDialog extends StatefulWidget {
  const _SaleDialog();
  @override
  State<_SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<_SaleDialog> {
  final porciones = TextEditingController();
  final precio = TextEditingController();
  final nota = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(
      title: const Text('Nueva venta'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              enabled: false,
              decoration: InputDecoration(labelText: 'Fecha', hintText: hoy)),
          const SizedBox(height: 8),
          TextField(
              controller: porciones,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Porciones vendidas')),
          const SizedBox(height: 8),
          TextField(
              controller: precio,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Precio por porción')),
          const SizedBox(height: 8),
          TextField(
              controller: nota, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final p = double.tryParse(porciones.text.replaceAll(',', '.')) ?? 0.0;
              final u = double.tryParse(precio.text.replaceAll(',', '.')) ?? 0.0;
              Navigator.pop(context, _NewSale(p, u, nota.text.trim().isEmpty ? null : nota.text.trim()));
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// ===== Pantalla: Caja =====

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
    final ing = moves
        .where((m) => m.tipo == 'Ingreso')
        .fold<double>(0, (p, m) => p + m.monto);
    final egr = moves
        .where((m) => m.tipo == 'Egreso')
        .fold<double>(0, (p, m) => p + m.monto);
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
    final res =
        await showDialog<CashCount>(context: context, builder: (_) => const _CountDialog());
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
          pw.Text('Generado: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
          if (ultimoArqueo != null) ...[
            pw.SizedBox(height: 8),
            pw.Text('Último arqueo: ${currency.format(ultimoArqueo!)}'),
            pw.Text('Diferencia: ${currency.format((ultimoArqueo ?? 0) - saldoTeorico)}'),
          ]
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'caja.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Movimientos'];
    s1.appendRow(xsRow(['Fecha', 'Tipo', 'Concepto', 'Monto']));
    for (final m in moves) {
      s1.appendRow(xsRow([m.fecha, m.tipo, m.concepto, m.monto]));
    }
    final s2 = excel['Arqueos'];
    s2.appendRow(xsRow(
        ['Fecha', 'Q200', 'Q100', 'Q50', 'Q20', 'Q10', 'Q5', 'Q1', 'Q0.50', 'Q0.25', 'Total']));
    for (final c in counts) {
      s2.appendRow(xsRow([
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
      ]));
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
      appBar: AppBar(
        title: const Text('Caja'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
            Text(ultimoArqueo == null
                ? 'Sin arqueo'
                : 'Último arqueo: ${currency.format(ultimoArqueo)}'),
          ]),
        ),
        if (dif != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Diferencia: ${currency.format(dif)}'))),
        const Divider(height: 1),
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
                  }),
        ),
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
              DropdownMenuItem(value: 'Egreso', child: Text('Egreso')),
            ],
            onChanged: (v) => setState(() => tipo = v ?? 'Ingreso'),
            decoration: const InputDecoration(labelText: 'Tipo'),
          ),
          const SizedBox(height: 8),
          TextField(controller: concepto, decoration: const InputDecoration(labelText: 'Concepto')),
          const SizedBox(height: 8),
          TextField(
              controller: monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto')),
          const SizedBox(height: 8),
          TextField(
              enabled: false,
              decoration: InputDecoration(labelText: 'Fecha', hintText: hoy)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final m = CashMove(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  fecha: hoy,
                  tipo: tipo,
                  concepto: concepto.text.trim(),
                  monto: double.tryParse(monto.text.replaceAll(',', '.')) ??
                      0.0);
              Navigator.pop(context, m);
            },
            child: const Text('Guardar')),
      ],
    );
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
    return StatefulBuilder(builder: (context, setSB) {
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
                          onChanged: (_) => setSB(() {}),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('Total contado: ${currency.format(_calcTotal())}')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                final denom = {
                  for (final e in ctrl.entries)
                    e.key: int.tryParse(e.value.text) ?? 0
                };
                final cc = CashCount(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    fecha: hoy,
                    denom: denom);
                Navigator.pop(context, cc);
              },
              child: const Text('Guardar')),
        ],
      );
    });
  }
}

/// ===== Reporte de Costos =====

class CostReportScreen extends StatefulWidget {
  const CostReportScreen({super.key});
  @override
  State<CostReportScreen> createState() => _CostReportScreenState();
}

class _CostReportScreenState extends State<CostReportScreen> {
  final repo = SalesRepo();
  List<Sale> sales = [];

  DateTime? from;
  DateTime? to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 1),
        initialDate: from ?? now);
    if (d != null) setState(() => from = d);
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 1),
        initialDate: to ?? now);
    if (d != null) setState(() => to = d);
  }

  Future<void> _load() async {
    sales = await repo.load();
    setState(() {});
  }

  List<Sale> get filtered {
    bool okDate(Sale s) {
      final d = DateTime.parse(s.fecha);
      if (from != null && d.isBefore(DateTime(from!.year, from!.month, from!.day))) return false;
      if (to != null && d.isAfter(DateTime(to!.year, to!.month, to!.day, 23, 59, 59))) return false;
      return true;
    }

    return sales.where(okDate).toList();
  }

  double get sumIngreso =>
      filtered.fold<double>(0, (p, s) => p + s.ingreso);
  double get sumMP => filtered.fold<double>(0, (p, s) => p + s.costoMP);
  double get sumMO => filtered.fold<double>(0, (p, s) => p + s.costoMO);
  double get sumGI => filtered.fold<double>(0, (p, s) => p + s.costoGI);
  double get sumCosto => filtered.fold<double>(0, (p, s) => p + s.costoTotal);
  double get sumGanancia => filtered.fold<double>(0, (p, s) => p + s.ganancia);

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Porciones', 'Ingreso', 'MP(PEPS)', 'MO', 'GI', 'Costo total', 'Ganancia'];
    final data = filtered
        .map((s) => [
              s.fecha,
              s.porciones.toStringAsFixed(0),
              currency.format(s.ingreso),
              currency.format(s.costoMP),
              currency.format(s.costoMO),
              currency.format(s.costoGI),
              currency.format(s.costoTotal),
              currency.format(s.ganancia)
            ])
        .toList();

    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Reporte de costos', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Generado: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Text(
              'Ingresos: ${currency.format(sumIngreso)} · MP: ${currency.format(sumMP)} · MO: ${currency.format(sumMO)} · GI: ${currency.format(sumGI)}'),
          pw.Text(
              'Costo total: ${currency.format(sumCosto)} · Ganancia neta: ${currency.format(sumGanancia)}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: data),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'costos.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Resumen'];
    s1.appendRow(xsRow(['Ingresos', 'MP(PEPS)', 'MO', 'GI', 'Costo total', 'Ganancia neta']));
    s1.appendRow(xsRow([sumIngreso, sumMP, sumMO, sumGI, sumCosto, sumGanancia]));

    final s2 = excel['Detalle'];
    s2.appendRow(xsRow(['Fecha', 'Porciones', 'Ingreso', 'MP(PEPS)', 'MO', 'GI', 'Costo Total', 'Ganancia']));
    for (final s in filtered) {
      s2.appendRow(xsRow([s.fecha, s.porciones, s.ingreso, s.costoMP, s.costoMO, s.costoGI, s.costoTotal, s.ganancia]));
    }

    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/costos.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de Costos'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportExcel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
                onPressed: _pickFrom,
                icon: const Icon(Icons.date_range),
                label: Text('Desde: ${from == null ? '—' : dateFmt.format(from!)}')),
            FilledButton.tonalIcon(
                onPressed: _pickTo,
                icon: const Icon(Icons.date_range_outlined),
                label: Text('Hasta: ${to == null ? '—' : dateFmt.format(to!)}')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ingresos: ${currency.format(sumIngreso)}'),
            Text('Materia prima (PEPS): ${currency.format(sumMP)}'),
            Text('Mano de obra: ${currency.format(sumMO)}'),
            Text('Gastos indirectos: ${currency.format(sumGI)}'),
            const SizedBox(height: 6),
            Text('Costo total: ${currency.format(sumCosto)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Ganancia neta: ${currency.format(sumGanancia)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Sin datos en el rango'))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    return ListTile(
                      title: Text('${s.fecha} · ${s.porciones.toStringAsFixed(0)} porciones'),
                      subtitle: Text(
                          'Ingresos: ${currency.format(s.ingreso)}  ·  Costo: ${currency.format(s.costoTotal)}'),
                      trailing: Text(currency.format(s.ganancia),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    );
                  }),
        ),
      ]),
    );
  }
}
