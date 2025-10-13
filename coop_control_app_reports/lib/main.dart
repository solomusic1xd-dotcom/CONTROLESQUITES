// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as ex;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ================== AJUSTES GENERALES ==================

void main() => runApp(const EsquitesApp());

final DateFormat dateFmt = DateFormat('yyyy-MM-dd');
final NumberFormat currency = NumberFormat.currency(locale: 'es_GT', symbol: 'Q ');

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

/// Excel >= 4.0: cada fila debe ser List<CellValue>
List<ex.CellValue> xsRow(List<dynamic> row) => row.map<ex.CellValue>((e) {
      if (e is int) return ex.IntCellValue(e);
      if (e is double) return ex.DoubleCellValue(e);
      if (e is num) return ex.DoubleCellValue(e.toDouble());
      if (e is DateTime) return ex.TextCellValue(dateFmt.format(e));
      return ex.TextCellValue(e?.toString() ?? '');
    }).toList();

/// Catálogo (para lista desplegable)
const List<String> kCatalogo = [
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

/// Receta por PORCIÓN (misma medida que el inventario)
final Map<String, double> kRecetaPorcion = {
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

/// Costos fijos por porción
const double kCostoMO = 3.57; // Mano de obra
const double kCostoGI = 1.67; // Gastos indirectos

/// ================== APP ==================

class EsquitesApp extends StatelessWidget {
  const EsquitesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CONTROL ESQUITES',
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
      appBar:
          AppBar(title: const Text('CONTROL ESQUITES'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardNav(
            icon: Icons.shopping_bag_outlined,
            title: 'Compras (PEPS)',
            subtitle: 'Registra compras por lote (fecha de hoy) y elimina si aún no se usó.',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ComprasScreen())),
          ),
          _CardNav(
            icon: Icons.inventory_2_outlined,
            title: 'Inventario PEPS',
            subtitle: 'Existencias por producto (suma de lotes pendientes).',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const InventarioScreen())),
          ),
          _CardNav(
            icon: Icons.point_of_sale_outlined,
            title: 'Ventas',
            subtitle:
                'Registra porciones e ingreso. Descuenta inventario PEPS y calcula costos.',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const VentasScreen())),
          ),
          _CardNav(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Caja',
            subtitle: 'Ingresos/Egresos y Arqueo con denominaciones.',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CajaScreen())),
          ),
          _CardNav(
            icon: Icons.receipt_long_outlined,
            title: 'Reporte de Costos',
            subtitle: 'Costo MP (PEPS) + MO + GI y Ganancia por periodo.',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CostosScreen())),
          ),
        ],
      ),
    );
  }
}

class _CardNav extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _CardNav(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
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

/// ================== MODELOS / STORAGE ==================

/// Lote de compra (también es el registro de compra)
class Lote {
  final String id; // timestamp
  final String fecha; // yyyy-MM-dd (HOY)
  final String producto; // catálogo
  final double unidadesTotales;
  final double unidadesRestantes;
  final double precioUnit; // por unidad

  Lote({
    required this.id,
    required this.fecha,
    required this.producto,
    required this.unidadesTotales,
    required this.unidadesRestantes,
    required this.precioUnit,
  });

  Lote copyWith({
    String? id,
    String? fecha,
    String? producto,
    double? unidadesTotales,
    double? unidadesRestantes,
    double? precioUnit,
  }) =>
      Lote(
        id: id ?? this.id,
        fecha: fecha ?? this.fecha,
        producto: producto ?? this.producto,
        unidadesTotales: unidadesTotales ?? this.unidadesTotales,
        unidadesRestantes: unidadesRestantes ?? this.unidadesRestantes,
        precioUnit: precioUnit ?? this.precioUnit,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'producto': producto,
        'unidadesTotales': unidadesTotales,
        'unidadesRestantes': unidadesRestantes,
        'precioUnit': precioUnit,
      };

  factory Lote.fromJson(Map<String, dynamic> j) => Lote(
        id: j['id'],
        fecha: j['fecha'],
        producto: j['producto'],
        unidadesTotales: (j['unidadesTotales'] as num).toDouble(),
        unidadesRestantes: (j['unidadesRestantes'] as num).toDouble(),
        precioUnit: (j['precioUnit'] as num).toDouble(),
      );
}

/// Venta
class Venta {
  final String id; // timestamp
  final String fecha; // yyyy-MM-dd
  final double porciones; // cantidad porciones vendidas
  final double ingreso; // total cobrado
  // calculados al momento (con PEPS)
  final double costoMP;
  final double costoMO;
  final double costoGI;

  double get costoTotal => costoMP + costoMO + costoGI;
  double get ganancia => ingreso - costoTotal;

  Venta({
    required this.id,
    required this.fecha,
    required this.porciones,
    required this.ingreso,
    required this.costoMP,
    required this.costoMO,
    required this.costoGI,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'porciones': porciones,
        'ingreso': ingreso,
        'costoMP': costoMP,
        'costoMO': costoMO,
        'costoGI': costoGI,
      };

  factory Venta.fromJson(Map<String, dynamic> j) => Venta(
        id: j['id'],
        fecha: j['fecha'],
        porciones: (j['porciones'] as num).toDouble(),
        ingreso: (j['ingreso'] as num).toDouble(),
        costoMP: (j['costoMP'] as num).toDouble(),
        costoMO: (j['costoMO'] as num).toDouble(),
        costoGI: (j['costoGI'] as num).toDouble(),
      );
}

/// Caja
class MovimientoCaja {
  final String id;
  final String fecha;
  final String tipo; // Ingreso / Egreso
  final String concepto;
  final double monto;

  MovimientoCaja(
      {required this.id,
      required this.fecha,
      required this.tipo,
      required this.concepto,
      required this.monto});

  Map<String, dynamic> toJson() =>
      {'id': id, 'fecha': fecha, 'tipo': tipo, 'concepto': concepto, 'monto': monto};

  factory MovimientoCaja.fromJson(Map<String, dynamic> j) =>
      MovimientoCaja(
          id: j['id'],
          fecha: j['fecha'],
          tipo: j['tipo'],
          concepto: j['concepto'],
          monto: (j['monto'] as num).toDouble());
}

class ArqueoCaja {
  final String id;
  final String fecha;
  final Map<String, int> denom; // '200': 1, '100': 0, etc.

  ArqueoCaja({required this.id, required this.fecha, required this.denom});

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

  factory ArqueoCaja.fromJson(Map<String, dynamic> j) => ArqueoCaja(
        id: j['id'],
        fecha: j['fecha'],
        denom: (j['denom'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        ),
      );
}

/// Storage
class Store {
  static const _kLotes = 'lotes_v1';
  static const _kVentas = 'ventas_v1';
  static const _kMovs = 'caja_movs_v1';
  static const _kArq = 'caja_arq_v1';

  /// Lotes
  Future<List<Lote>> loadLotes() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kLotes);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Lote.fromJson).toList();
  }

  Future<void> saveLotes(List<Lote> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLotes, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }

  /// Ventas
  Future<List<Venta>> loadVentas() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kVentas);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Venta.fromJson).toList();
  }

  Future<void> saveVentas(List<Venta> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kVentas, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }

  /// Caja
  Future<List<MovimientoCaja>> loadMovs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kMovs);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(MovimientoCaja.fromJson).toList();
  }

  Future<void> saveMovs(List<MovimientoCaja> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMovs, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }

  Future<List<ArqueoCaja>> loadArqueos() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kArq);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(ArqueoCaja.fromJson).toList();
  }

  Future<void> saveArqueos(List<ArqueoCaja> xs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kArq, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }
}

final store = Store();

/// ================== LÓGICA PEPS (FIFO) ==================

class PEPSService {
  /// Verifica si hay stock suficiente para N porciones según receta.
  Future<(bool ok, List<String> faltantes)> hayStockParaPorciones(
      double porciones) async {
    final lotes = await store.loadLotes();
    final byProd = <String, double>{};
    for (final l in lotes) {
      final k = _norm(l.producto);
      byProd[k] = (byProd[k] ?? 0) + l.unidadesRestantes;
    }
    final falt = <String>[];
    kRecetaPorcion.forEach((k, v) {
      final need = v * porciones;
      if ((byProd[k] ?? 0) + 1e-9 < need) {
        falt.add(
            '${k.toUpperCase()}: falta ${(need - (byProd[k] ?? 0)).toStringAsFixed(3)}');
      }
    });
    return (falt.isEmpty, falt);
  }

  /// Descuenta del inventario según receta*porciones. Devuelve costo MP total (PEPS).
  Future<double> consumirPorciones(double porciones) async {
    final lotes = await store.loadLotes();
    // Orden FIFO por fecha e id
    lotes.sort((a, b) => a.fecha != b.fecha
        ? a.fecha.compareTo(b.fecha)
        : a.id.compareTo(b.id));
    double costoMP = 0.0;

    for (final entry in kRecetaPorcion.entries) {
      final prod = entry.key;
      double rest = entry.value * porciones; // lo que necesito consumir
      for (int i = 0; i < lotes.length && rest > 1e-12; i++) {
        if (_norm(lotes[i].producto) != prod) continue;
        final toma = rest <= lotes[i].unidadesRestantes
            ? rest
            : lotes[i].unidadesRestantes;
        if (toma <= 0) continue;
        costoMP += toma * lotes[i].precioUnit;
        lotes[i] = lotes[i]
            .copyWith(unidadesRestantes: lotes[i].unidadesRestantes - toma);
        rest -= toma;
      }
      // (asumimos validado previamente)
    }
    await store.saveLotes(lotes);
    return costoMP;
  }
}

/// ================== PANTALLAS ==================

/// ---------- COMPRAS ----------
class ComprasScreen extends StatefulWidget {
  const ComprasScreen({super.key});
  @override
  State<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends State<ComprasScreen> {
  List<Lote> lotes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    lotes = await store.loadLotes();
    lotes.sort((a, b) => b.fecha.compareTo(a.fecha));
    setState(() {});
  }

  Future<void> _add() async {
    final res = await showDialog<Lote>(
        context: context, builder: (_) => const _DlgCompra());
    if (res != null) {
      lotes.add(res);
      await store.saveLotes(lotes);
      setState(() {});
    }
  }

  Future<void> _delete(Lote l) async {
    // Solo si no se ha consumido (restantes == totales)
    if (l.unidadesRestantes + 1e-9 < l.unidadesTotales) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No puedes borrar: el lote ya fue usado.')));
      return;
    }
    final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                  title: const Text('Eliminar compra'),
                  content: const Text('¿Seguro que deseas eliminarla?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Eliminar')),
                  ],
                )) ??
        false;
    if (!ok) return;
    lotes.removeWhere((e) => e.id == l.id);
    await store.saveLotes(lotes);
    setState(() {});
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Producto', 'Unid', 'Restan', 'Precio', 'Total'];
    final rows = lotes
        .map((l) => [
              l.fecha,
              l.producto,
              l.unidadesTotales.toStringAsFixed(3),
              l.unidadesRestantes.toStringAsFixed(3),
              currency.format(l.precioUnit),
              currency.format(l.unidadesTotales * l.precioUnit)
            ])
        .toList();
    pdf.addPage(pw.MultiPage(build: (_) {
      return [
        pw.Header(level: 0, child: pw.Text('Compras (PEPS)')),
        pw.Table.fromTextArray(headers: headers, data: rows),
      ];
    }));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'compras.pdf');
  }

  Future<void> _exportXlsx() async {
    final excel = ex.Excel.createExcel();
    final s = excel['Compras'];
    s.appendRow(xsRow(
        ['Fecha', 'Producto', 'Unidades', 'Restantes', 'Precio Unit', 'Total']));
    for (final l in lotes) {
      s.appendRow(xsRow([
        l.fecha,
        l.producto,
        l.unidadesTotales,
        l.unidadesRestantes,
        l.precioUnit,
        l.unidadesTotales * l.precioUnit
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
        title: const Text('Compras (PEPS)'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportXlsx();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _add, icon: const Icon(Icons.add), label: const Text('Compra')),
      body: lotes.isEmpty
          ? const Center(child: Text('Sin compras'))
          : ListView.separated(
              itemCount: lotes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final l = lotes[i];
                return ListTile(
                  title: Text(l.producto),
                  subtitle: Text(
                      'Fecha: ${l.fecha}\nUnidades: ${l.unidadesTotales.toStringAsFixed(3)} · Restan: ${l.unidadesRestantes.toStringAsFixed(3)} · Precio: ${currency.format(l.precioUnit)}'),
                  trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(l)),
                  isThreeLine: true,
                );
              }),
    );
  }
}

class _DlgCompra extends StatefulWidget {
  const _DlgCompra();
  @override
  State<_DlgCompra> createState() => _DlgCompraState();
}

class _DlgCompraState extends State<_DlgCompra> {
  String prod = kCatalogo.first;
  final unidades = TextEditingController();
  final precio = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(
      title: const Text('Nueva compra'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Fecha: $hoy (automática)'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: prod,
              decoration: const InputDecoration(labelText: 'Producto'),
              items:
                  kCatalogo.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => prod = v ?? prod),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: unidades,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unidades compradas'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: precio,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio por unidad'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final u = double.tryParse(unidades.text.replaceAll(',', '.')) ?? 0;
              final p = double.tryParse(precio.text.replaceAll(',', '.')) ?? 0;
              final l = Lote(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  fecha: hoy,
                  producto: prod,
                  unidadesTotales: u,
                  unidadesRestantes: u,
                  precioUnit: p);
              Navigator.pop(context, l);
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// ---------- INVENTARIO (vista agregada por producto) ----------
class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});
  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  List<Lote> lotes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    lotes = await store.loadLotes();
    setState(() {});
  }

  Map<String, (double exist, double valor)> _agregado() {
    final m = <String, (double, double)>{};
    for (final l in lotes) {
      final k = l.producto;
      final par = m[k];
      final ne = (par?.$1 ?? 0) + l.unidadesRestantes;
      final nv = (par?.$2 ?? 0) + l.unidadesRestantes * l.precioUnit;
      m[k] = (ne, nv);
    }
    return m;
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final data = _agregado();
    final headers = ['Producto', 'Existencia', 'Valor'];
    final rows = data.entries
        .map((e) => [
              e.key,
              e.value.$1.toStringAsFixed(3),
              currency.format(e.value.$2)
            ])
        .toList();
    final total = data.values.fold<double>(0, (p, e) => p + e.$2);
    pdf.addPage(pw.MultiPage(build: (_) {
      return [
        pw.Header(level: 0, child: pw.Text('Inventario (PEPS)')),
        pw.Table.fromTextArray(headers: headers, data: rows),
        pw.SizedBox(height: 8),
        pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Valor total: ${currency.format(total)}')),
      ];
    }));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'inventario.pdf');
  }

  Future<void> _exportXlsx() async {
    final excel = ex.Excel.createExcel();
    final s = excel['Inventario'];
    s.appendRow(xsRow(['Producto', 'Existencia', 'Valor']));
    final data = _agregado();
    for (final e in data.entries) {
      s.appendRow(xsRow([e.key, e.value.$1, e.value.$2]));
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
    final data = _agregado();
    final total = data.values.fold<double>(0, (p, e) => p + e.$2);
    if (data.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Inventario (PEPS)'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'pdf') _exportPdf();
                if (v == 'xlsx') _exportXlsx();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
                PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
              ],
            ),
          ],
        ),
        body: const Center(child: Text('Sin existencias')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario (PEPS)'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportXlsx();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Productos: ${data.length}'),
                Text('Valor total: ${currency.format(total)}'),
              ],
            ),
          ),
          const Divider(height: 1),
          ...data.entries.map((e) => ListTile(
                title: Text(e.key),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Exist: ${e.value.$1.toStringAsFixed(3)}'),
                    Text(currency.format(e.value.$2)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// ---------- VENTAS ----------
class VentasScreen extends StatefulWidget {
  const VentasScreen({super.key});
  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> {
  List<Venta> ventas = [];
  final peps = PEPSService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ventas = await store.loadVentas();
    ventas.sort((a, b) => b.fecha.compareTo(a.fecha));
    setState(() {});
  }

  Future<void> _add() async {
    final res =
        await showDialog<_VentaInput>(context: context, builder: (_) => const _DlgVenta());
    if (res == null) return;

    // validar stock
    final chk = await peps.hayStockParaPorciones(res.porciones);
    if (!chk.ok) {
      await showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Faltantes'),
                content: Text(chk.faltantes.join('\n')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendido'))
                ],
              ));
      return;
    }

    // consumir y calcular costo
    final costoMP = await peps.consumirPorciones(res.porciones);
    final costoMO = kCostoMO * res.porciones;
    final costoGI = kCostoGI * res.porciones;

    final v = Venta(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fecha: dateFmt.format(DateTime.now()),
      porciones: res.porciones,
      ingreso: res.ingreso,
      costoMP: costoMP,
      costoMO: costoMO,
      costoGI: costoGI,
    );
    ventas.add(v);
    await store.saveVentas(ventas);

    // sugerencia: ingresar a caja como Ingreso
    final movs = await store.loadMovs();
    movs.add(MovimientoCaja(
        id: v.id,
        fecha: v.fecha,
        tipo: 'Ingreso',
        concepto: 'Venta ${v.porciones.toStringAsFixed(0)} porciones',
        monto: v.ingreso));
    await store.saveMovs(movs);

    setState(() {});
  }

  Map<String, double> _resumenPorDia() {
    final m = <String, double>{};
    for (final v in ventas) {
      m[v.fecha] = (m[v.fecha] ?? 0) + v.ingreso;
    }
    return m;
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Porciones', 'Ingreso', 'MP', 'MO', 'GI', 'Total', 'Ganancia'];
    final rows = ventas
        .map((s) => [
              s.fecha,
              s.porciones.toStringAsFixed(0),
              currency.format(s.ingreso),
              currency.format(s.costoMP),
              currency.format(s.costoMO),
              currency.format(s.costoGI),
              currency.format(s.costoTotal),
              currency.format(s.ganancia),
            ])
        .toList();
    final totalIng = ventas.fold<double>(0, (p, s) => p + s.ingreso);
    final totalGan = ventas.fold<double>(0, (p, s) => p + s.ganancia);
    pdf.addPage(pw.MultiPage(build: (_) {
      return [
        pw.Header(level: 0, child: pw.Text('Ventas')),
        pw.Text('Ingresos: ${currency.format(totalIng)}'),
        pw.Text('Ganancia neta: ${currency.format(totalGan)}'),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(headers: headers, data: rows),
      ];
    }));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'ventas.pdf');
  }

  Future<void> _exportXlsx() async {
    final excel = ex.Excel.createExcel();
    final s = excel['Ventas'];
    s.appendRow(xsRow(['Fecha', 'Porciones', 'Ingreso', 'MP', 'MO', 'GI', 'Total', 'Ganancia']));
    for (final v in ventas) {
      s.appendRow(xsRow([
        v.fecha,
        v.porciones,
        v.ingreso,
        v.costoMP,
        v.costoMO,
        v.costoGI,
        v.costoTotal,
        v.ganancia
      ]));
    }
    final res = excel['Resumen_por_dia'];
    res.appendRow(xsRow(['Día', 'Total']));
    _resumenPorDia().forEach((k, val) {
      res.appendRow(xsRow([k, val]));
    });

    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ventas.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final totalIng = ventas.fold<double>(0, (p, s) => p + s.ingreso);
    final totalGan = ventas.fold<double>(0, (p, s) => p + s.ganancia);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportXlsx();
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
      body: ventas.isEmpty
          ? const Center(child: Text('Sin ventas registradas'))
          : ListView.separated(
              itemCount: ventas.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ingresos: ${currency.format(totalIng)}'),
                        Text('Ganancia neta: ${currency.format(totalGan)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  );
                }
                final v = ventas[i - 1];
                return ListTile(
                  title: Text('${v.fecha} · ${v.porciones.toStringAsFixed(0)} porciones'),
                  subtitle: Text(
                      'Ingreso: ${currency.format(v.ingreso)} · MP: ${currency.format(v.costoMP)} · MO: ${currency.format(v.costoMO)} · GI: ${currency.format(v.costoGI)}'),
                  trailing:
                      Text('Ganancia\n${currency.format(v.ganancia)}', textAlign: TextAlign.right),
                  isThreeLine: true,
                );
              }),
    );
  }
}

class _VentaInput {
  final double porciones;
  final double ingreso;
  _VentaInput(this.porciones, this.ingreso);
}

class _DlgVenta extends StatefulWidget {
  const _DlgVenta();
  @override
  State<_DlgVenta> createState() => _DlgVentaState();
}

class _DlgVentaState extends State<_DlgVenta> {
  final porciones = TextEditingController();
  final ingreso = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar venta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: porciones,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Porciones'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ingreso,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Ingreso total'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final p =
                  double.tryParse(porciones.text.replaceAll(',', '.')) ?? 0;
              final i =
                  double.tryParse(ingreso.text.replaceAll(',', '.')) ?? 0;
              Navigator.pop(context, _VentaInput(p, i));
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// ---------- CAJA ----------
class CajaScreen extends StatefulWidget {
  const CajaScreen({super.key});
  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  List<MovimientoCaja> movs = [];
  List<ArqueoCaja> arqueos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    movs = await store.loadMovs();
    arqueos = await store.loadArqueos();
    setState(() {});
  }

  double get saldoTeorico {
    final ing =
        movs.where((m) => m.tipo == 'Ingreso').fold<double>(0, (p, m) => p + m.monto);
    final egr =
        movs.where((m) => m.tipo == 'Egreso').fold<double>(0, (p, m) => p + m.monto);
    return ing - egr;
  }

  double? get ultimoArqueo =>
      arqueos.isEmpty ? null : (arqueos..sort((a, b) => b.fecha.compareTo(a.fecha))).first.total;

  Future<void> _addMov() async {
    final res = await showDialog<MovimientoCaja>(
        context: context, builder: (_) => const _DlgMovCaja());
    if (res != null) {
      movs.add(res);
      await store.saveMovs(movs);
      setState(() {});
    }
  }

  Future<void> _addArqueo() async {
    final res = await showDialog<ArqueoCaja>(
        context: context, builder: (_) => const _DlgArqueo());
    if (res != null) {
      arqueos.add(res);
      await store.saveArqueos(arqueos);
      setState(() {});
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha', 'Tipo', 'Concepto', 'Monto'];
    final rows = movs
        .map((m) => [m.fecha, m.tipo, m.concepto, currency.format(m.monto)])
        .toList();
    pdf.addPage(pw.MultiPage(build: (_) {
      return [
        pw.Header(level: 0, child: pw.Text('Caja')),
        pw.Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
        if (ultimoArqueo != null) pw.Text('Último arqueo: ${currency.format(ultimoArqueo!)}'),
        if (ultimoArqueo != null)
          pw.Text('Diferencia: ${currency.format(ultimoArqueo! - saldoTeorico)}'),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(headers: headers, data: rows),
      ];
    }));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'caja.pdf');
  }

  Future<void> _exportXlsx() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Caja_Movimientos'];
    s1.appendRow(xsRow(['Fecha', 'Tipo', 'Concepto', 'Monto']));
    for (final m in movs) {
      s1.appendRow(xsRow([m.fecha, m.tipo, m.concepto, m.monto]));
    }
    final s2 = excel['Caja_Arqueos'];
    s2.appendRow(xsRow(
        ['Fecha', 'Q200', 'Q100', 'Q50', 'Q20', 'Q10', 'Q5', 'Q1', 'Q0.50', 'Q0.25', 'Total']));
    for (final a in arqueos) {
      s2.appendRow(xsRow([
        a.fecha,
        a.denom['200'] ?? 0,
        a.denom['100'] ?? 0,
        a.denom['50'] ?? 0,
        a.denom['20'] ?? 0,
        a.denom['10'] ?? 0,
        a.denom['5'] ?? 0,
        a.denom['1'] ?? 0,
        a.denom['0.50'] ?? 0,
        a.denom['0.25'] ?? 0,
        a.total
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
    final dif =
        ultimoArqueo == null ? null : (ultimoArqueo! - saldoTeorico);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportXlsx();
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
              onPressed: _addMov,
              icon: const Icon(Icons.swap_vert),
              label: const Text('Movimiento')),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
              heroTag: 'm2',
              onPressed: _addArqueo,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Arqueo')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
                Text(ultimoArqueo == null
                    ? 'Sin arqueo'
                    : 'Arqueo: ${currency.format(ultimoArqueo)}'),
              ],
            ),
          ),
          if (dif != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Diferencia: ${currency.format(dif)}')),
            ),
          const Divider(),
          Expanded(
            child: movs.isEmpty
                ? const Center(child: Text('Sin movimientos'))
                : ListView.separated(
                    itemCount: movs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = movs[i];
                      return ListTile(
                        leading: Icon(
                            m.tipo == 'Ingreso'
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: m.tipo == 'Ingreso'
                                ? Colors.green
                                : Colors.red),
                        title: Text('${m.tipo} · ${currency.format(m.monto)}'),
                        subtitle: Text('${m.concepto}\n${m.fecha}'),
                        isThreeLine: true,
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              movs.removeAt(i);
                              await store.saveMovs(movs);
                              setState(() {});
                            }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DlgMovCaja extends StatefulWidget {
  const _DlgMovCaja();
  @override
  State<_DlgMovCaja> createState() => _DlgMovCajaState();
}

class _DlgMovCajaState extends State<_DlgMovCaja> {
  String tipo = 'Ingreso';
  final concepto = TextEditingController();
  final monto = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(
      title: const Text('Nuevo movimiento'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          TextField(
            controller: concepto,
            decoration: const InputDecoration(labelText: 'Concepto'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: monto,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monto'),
          ),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: Text('Fecha: $hoy')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final d = MovimientoCaja(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  fecha: hoy,
                  tipo: tipo,
                  concepto: concepto.text.trim(),
                  monto: double.tryParse(monto.text.replaceAll(',', '.')) ??
                      0.0);
              Navigator.pop(context, d);
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

class _DlgArqueo extends StatefulWidget {
  const _DlgArqueo();
  @override
  State<_DlgArqueo> createState() => _DlgArqueoState();
}

class _DlgArqueoState extends State<_DlgArqueo> {
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

  double _total() {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                child: Text('Total contado: ${currency.format(_total())}'),
              ),
              Align(alignment: Alignment.centerLeft, child: Text('Fecha: $hoy')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                final denom = {
                  for (final e in ctrl.entries)
                    e.key: int.tryParse(e.value.text) ?? 0
                };
                Navigator.pop(
                    context,
                    ArqueoCaja(
                        id: DateTime.now()
                            .millisecondsSinceEpoch
                            .toString(),
                        fecha: hoy,
                        denom: denom));
              },
              child: const Text('Guardar')),
        ],
      );
    });
  }
}

/// ---------- COSTOS ----------
class CostosScreen extends StatefulWidget {
  const CostosScreen({super.key});
  @override
  State<CostosScreen> createState() => _CostosScreenState();
}

class _CostosScreenState extends State<CostosScreen> {
  List<Venta> ventas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ventas = await store.loadVentas();
    setState(() {});
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final filtered = ventas; // si quisieras rango de fechas, aquí filtras
    final headers = ['Fecha', 'Porciones', 'Ingreso', 'MP (PEPS)', 'MO', 'GI', 'Costo Total', 'Ganancia'];
    final rows = filtered
        .map((s) => [
              s.fecha,
              s.porciones.toStringAsFixed(0),
              currency.format(s.ingreso),
              currency.format(s.costoMP),
              currency.format(s.costoMO),
              currency.format(s.costoGI),
              currency.format(s.costoTotal),
              currency.format(s.ganancia),
            ])
        .toList();
    final ingreso = filtered.fold<double>(0, (p, s) => p + s.ingreso);
    final costoMP = filtered.fold<double>(0, (p, s) => p + s.costoMP);
    final costoMO = filtered.fold<double>(0, (p, s) => p + s.costoMO);
    final costoGI = filtered.fold<double>(0, (p, s) => p + s.costoGI);
    final gan = filtered.fold<double>(0, (p, s) => p + s.ganancia);

    pdf.addPage(pw.MultiPage(build: (_) {
      return [
        pw.Header(level: 0, child: pw.Text('Reporte de Costos')),
        pw.Text('Ingreso: ${currency.format(ingreso)}'),
        pw.Text('MP (PEPS): ${currency.format(costoMP)}'),
        pw.Text('MO: ${currency.format(costoMO)}'),
        pw.Text('GI: ${currency.format(costoGI)}'),
        pw.Text('Ganancia neta: ${currency.format(gan)}'),
        pw.SizedBox(height: 8),
        pw.Table.fromTextArray(headers: headers, data: rows),
      ];
    }));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'costos.pdf');
  }

  Future<void> _exportXlsx() async {
    final excel = ex.Excel.createExcel();
    final s = excel['Costos'];
    s.appendRow(xsRow(
        ['Fecha', 'Porciones', 'Ingreso', 'MP (PEPS)', 'MO', 'GI', 'Costo Total', 'Ganancia']));
    for (final v in ventas) {
      s.appendRow(xsRow(
          [v.fecha, v.porciones, v.ingreso, v.costoMP, v.costoMO, v.costoGI, v.costoTotal, v.ganancia]));
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
    final ingreso = ventas.fold<double>(0, (p, s) => p + s.ingreso);
    final costoMP = ventas.fold<double>(0, (p, s) => p + s.costoMP);
    final costoMO = ventas.fold<double>(0, (p, s) => p + s.costoMO);
    final costoGI = ventas.fold<double>(0, (p, s) => p + s.costoGI);
    final gan = ventas.fold<double>(0, (p, s) => p + s.ganancia);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de Costos'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              if (v == 'xlsx') _exportXlsx();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exportar PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Exportar Excel')),
            ],
          )
        ],
      ),
      body: ventas.isEmpty
          ? const Center(child: Text('Sin ventas aún'))
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ingreso: ${currency.format(ingreso)}'),
                      Text('MP (PEPS): ${currency.format(costoMP)}'),
                      Text('MO: ${currency.format(costoMO)}'),
                      Text('GI: ${currency.format(costoGI)}'),
                      Text('Ganancia neta: ${currency.format(gan)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ...ventas.map((v) => ListTile(
                      title: Text('${v.fecha} · ${v.porciones.toStringAsFixed(0)} porciones'),
                      subtitle: Text(
                          'Ingreso: ${currency.format(v.ingreso)}  ·  Costo: ${currency.format(v.costoTotal)}'),
                      trailing: Text(currency.format(v.ganancia),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    )),
              ],
            ),
    );
  }
}
