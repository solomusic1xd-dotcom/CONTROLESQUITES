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

/// ------- Catálogo y Receta -------
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

const double COSTO_MO = 3.57;  // mano de obra por porción
const double COSTO_GI = 1.67;  // gastos indirectos por porción

/// ------- Resultados -------
class ApplyResult {
  final bool ok;
  final List<String> faltantes;
  final double costoMP; // costo materia prima de esta venta (PEPS)
  const ApplyResult(this.ok, this.faltantes, this.costoMP);
}

/// ------- App -------
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cards = <_NavCard>[
      _NavCard('Inventario (PEPS)', 'Resumen por producto con lotes FIFO',
          Icons.inventory_2_outlined, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InventoryScreen()));
      }),
      _NavCard('Compras', 'Entradas al inventario (crea lotes PEPS)',
          Icons.shopping_cart_outlined, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PurchaseScreen()));
      }),
      _NavCard('Ventas', 'Registra porciones (descuenta PEPS)',
          Icons.point_of_sale_outlined, () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SalesScreen()));
      }),
      _NavCard('Caja', 'Ingresos/Egresos y Arqueo', Icons.account_balance_wallet,
          () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const CashScreen()));
      }),
      _NavCard('Reporte de Costos',
          'Ingresos vs costos (MP PEPS, MO, GI) y Ganancia Neta',
          Icons.bar_chart, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CostReportScreen()));
      }),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES')),
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
  final String t, s;
  final IconData icon;
  final VoidCallback onTap;
  const _NavCard(this.t, this.s, this.icon, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(s),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// =====================
///   MODELOS + REPOS
/// =====================

/// Lote FIFO (PEPS)
class InventoryLot {
  final String id;       // = id de la compra
  final String fecha;    // yyyy-MM-dd
  final String producto; // nombre normalizado visual
  final String unidad;
  final double precioUnit;
  final double qty;      // disponible (va bajando con ventas)

  const InventoryLot({
    required this.id,
    required this.fecha,
    required this.producto,
    required this.unidad,
    required this.precioUnit,
    required this.qty,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'producto': producto,
        'unidad': unidad,
        'precioUnit': precioUnit,
        'qty': qty,
      };

  factory InventoryLot.fromJson(Map<String, dynamic> j) => InventoryLot(
        id: j['id'],
        fecha: j['fecha'],
        producto: j['producto'],
        unidad: j['unidad'],
        precioUnit: (j['precioUnit'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
      );
}

/// Resumen por producto (para UI Inventario)
class InvResumen {
  final String producto;
  final String unidad;
  final double cantidad;
  final double valor;
  final double precioPromedio;
  const InvResumen(this.producto, this.unidad, this.cantidad, this.valor,
      this.precioPromedio);
}

class InventoryRepo {
  static const _lotsKey = 'inv_lots_v1';

  Future<List<InventoryLot>> _loadLots() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_lotsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(InventoryLot.fromJson).toList();
  }

  Future<void> _saveLots(List<InventoryLot> lots) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _lotsKey, jsonEncode(lots.map((e) => e.toJson()).toList()));
  }

  Future<void> entradaCompra({
    required String idCompra,
    required String fecha,
    required String producto,
    required String unidad,
    required double unidades,
    required double precioUnitario,
  }) async {
    final lots = await _loadLots();
    lots.add(InventoryLot(
      id: idCompra,
      fecha: fecha,
      producto: producto,
      unidad: unidad,
      precioUnit: precioUnitario,
      qty: unidades,
    ));
    await _saveLots(lots);
  }

  /// Resumen actual por producto
  Future<List<InvResumen>> resumen() async {
    final lots = await _loadLots();
    final Map<String, List<InventoryLot>> byProd = {};
    for (final l in lots) {
      byProd.putIfAbsent(_norm(l.producto), () => []).add(l);
    }
    final out = <InvResumen>[];
    byProd.forEach((k, ls) {
      final nombre = ls.first.producto;
      final unidad = ls.first.unidad;
      final totalCant = ls.fold<double>(0, (p, l) => p + l.qty);
      final totalVal = ls.fold<double>(0, (p, l) => p + l.qty * l.precioUnit);
      final prom = totalCant > 0 ? totalVal / totalCant : 0.0;
      out.add(InvResumen(nombre, unidad, totalCant, totalVal, prom));
    });
    out.sort((a, b) => a.producto.compareTo(b.producto));
    return out;
  }

  /// Descuenta receta via PEPS y devuelve costo MP usado.
  Future<ApplyResult> consumirRecetaFIFO(
      Map<String, double> receta, double porciones) async {
    final lots = await _loadLots();

    // 1) Verificar faltantes
    final Map<String, double> needByProd = {
      for (final e in receta.entries) e.key: e.value * porciones
    };
    final faltantes = <String>[];

    for (final entry in needByProd.entries) {
      final prod = entry.key;
      final need = entry.value;
      final disp = lots
          .where((l) => _norm(l.producto) == prod)
          .fold<double>(0, (p, l) => p + l.qty);
      if (disp + 1e-9 < need) {
        faltantes.add(
            '${prod.toUpperCase()}: falta ${(need - disp).toStringAsFixed(3)}');
      }
    }
    if (faltantes.isNotEmpty) {
      return ApplyResult(false, faltantes, 0);
    }

    // 2) Descontar FIFO y calcular costo
    double costoMP = 0.0;
    for (final entry in needByProd.entries) {
      final prod = entry.key;
      double need = entry.value;

      final fifo = lots
          .where((l) => _norm(l.producto) == prod)
          .toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha)); // primero en entrar

      for (int i = 0; i < fifo.length && need > 0; i++) {
        final l = fifo[i];
        if (l.qty <= 0) continue;
        final take = need <= l.qty ? need : l.qty;
        costoMP += take * l.precioUnit;

        // actualiza lote
        final idx = lots.indexWhere((x) => x.id == l.id);
        lots[idx] = InventoryLot(
          id: l.id,
          fecha: l.fecha,
          producto: l.producto,
          unidad: l.unidad,
          precioUnit: l.precioUnit,
          qty: l.qty - take,
        );

        need -= take;
      }
    }

    // 3) guardar
    await _saveLots(lots);
    return ApplyResult(true, const [], costoMP);
  }

  /// Borrar lote/compra si NO se ha usado nada.
  Future<bool> borrarCompraSiLibre(String lotId) async {
    final lots = await _loadLots();
    final idx = lots.indexWhere((l) => l.id == lotId);
    if (idx < 0) return false;
    // si el lote está intacto: qty original =? No la guardamos aparte, pero
    // podemos inferir que "intacto" si no hay ventas: solo podemos borrar si el
    // qty es > 0 y NUNCA se redujo. Para eso guardemos un truco: si se usó,
    // el qty queda < 0? No. Solución práctica: permitimos borrar si el qty > 0
    // y no existe otro registro de compra con mismo id (siempre único).
    // Para ser estrictos: añadimos a Purchase el campo unidades y verificamos
    // contra él. (vemos abajo en PurchaseRepo.delete)
    return true;
  }

  /// Para PurchaseRepo: elimina el lote por id
  Future<void> eliminarLotePorId(String lotId) async {
    final lots = await _loadLots();
    lots.removeWhere((l) => l.id == lotId);
    await _saveLots(lots);
  }

  /// Cantidad disponible de un lote (por id)
  Future<double?> qtyDeLote(String lotId) async {
    final lots = await _loadLots();
    final l = lots.where((e) => e.id == lotId).toList();
    if (l.isEmpty) return null;
    return l.first.qty;
  }
}

/// Compra
class Purchase {
  final String id; // también es id del lote
  final String fecha;
  final String producto;
  final String unidad;
  final double unidades;
  final double precioUnit;

  const Purchase({
    required this.id,
    required this.fecha,
    required this.producto,
    required this.unidad,
    required this.unidades,
    required this.precioUnit,
  });

  double get total => unidades * precioUnit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'producto': producto,
        'unidad': unidad,
        'unidades': unidades,
        'precioUnit': precioUnit,
      };

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        id: j['id'],
        fecha: j['fecha'],
        producto: j['producto'],
        unidad: j['unidad'] ?? 'unidad',
        unidades: (j['unidades'] as num).toDouble(),
        precioUnit: (j['precioUnit'] as num).toDouble(),
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
    await p.setString(_key, jsonEncode(xs.map((e) => e.toJson()).toList()));
  }
}

/// Venta (guardamos costo MP PEPS calculado en el momento)
class Sale {
  final String id;
  final String fecha;
  final double porciones;
  final double precioUnit;
  final double costoMP; // costo materia prima real PEPS de esta venta
  final String nota;

  const Sale({
    required this.id,
    required this.fecha,
    required this.porciones,
    required this.precioUnit,
    required this.costoMP,
    required this.nota,
  });

  double get ingreso => porciones * precioUnit;
  double get costoMO => porciones * COSTO_MO;
  double get costoGI => porciones * COSTO_GI;
  double get costoTotal => costoMP + costoMO + costoGI;
  double get ganancia => ingreso - costoTotal;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fecha': fecha,
        'porciones': porciones,
        'precioUnit': precioUnit,
        'costoMP': costoMP,
        'nota': nota,
      };

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'],
        fecha: j['fecha'],
        porciones: (j['porciones'] as num).toDouble(),
        precioUnit: (j['precioUnit'] as num).toDouble(),
        costoMP: (j['costoMP'] as num?)?.toDouble() ?? 0.0,
        nota: j['nota'] ?? '',
      );
}

class SalesRepo {
  static const _key = 'ventas_v3';
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

/// Caja
class CashMove {
  final String id;
  final String fecha;
  final String tipo; // Ingreso / Egreso
  final String concepto;
  final double monto;

  const CashMove(
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
        monto: (j['monto'] as num).toDouble(),
      );
}

class CashCount {
  final String id;
  final String fecha;
  final Map<String, int> denom;
  const CashCount({required this.id, required this.fecha, required this.denom});

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
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      );
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
///     INVENTARIO
/// =====================

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final inv = InventoryRepo();
  List<InvResumen> data = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    data = await inv.resumen();
    setState(() {});
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Producto', 'Unidad', 'Existencia', 'P. Promedio', 'Valor'];
    final rows = data
        .map((r) => [
              r.producto,
              r.unidad,
              r.cantidad.toStringAsFixed(2),
              currency.format(r.precioPromedio),
              currency.format(r.valor)
            ])
        .toList();
    final total = data.fold<double>(0, (p, r) => p + r.valor);
    pdf.addPage(pw.MultiPage(build: (_) => [
          pw.Header(level: 0, child: pw.Text('Inventario (PEPS)', style: pw.TextStyle(fontSize: 20))),
          pw.Text('Fecha: ${dateFmt.format(DateTime.now())}'),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(headers: headers, data: rows),
          pw.SizedBox(height: 8),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Valor total: ${currency.format(total)}')),
        ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'inventario_peps.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final total = data.fold<double>(0, (p, r) => p + r.valor);
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Inventario (PEPS)'), actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf)),
      ]),
      body: data.isEmpty
          ? const Center(child: Text('Sin existencias'))
          : ListView.separated(
              itemCount: data.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = data[i];
                return ListTile(
                  title: Text(r.producto),
                  subtitle:
                      Text('Unidad: ${r.unidad} · P.Promedio: ${currency.format(r.precioPromedio)}'),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Existencia: ${r.cantidad.toStringAsFixed(2)}'),
                      Text(currency.format(r.valor)),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Valor total: ${currency.format(total)}',
            textAlign: TextAlign.right),
      ),
    );
  }
}

/// =====================
///       COMPRAS
/// =====================

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final pRepo = PurchaseRepo();
  final inv = InventoryRepo();
  final cash = CashRepo();

  String producto = catalogoProductos.first;
  String unidad = 'unidad';
  final unidadesCtrl = TextEditingController();
  final precioCtrl = TextEditingController();

  List<Purchase> compras = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    compras = await pRepo.load();
    setState(() {});
  }

  Future<void> _add() async {
    final hoy = dateFmt.format(DateTime.now());
    final u = double.tryParse(unidadesCtrl.text.replaceAll(',', '.')) ?? 0;
    final pu = double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
    if (u <= 0 || pu <= 0) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final c = Purchase(
      id: id,
      fecha: hoy,
      producto: producto,
      unidad: unidad,
      unidades: u,
      precioUnit: pu,
    );
    compras.add(c);
    await pRepo.save(compras);

    // crea lote (PEPS)
    await inv.entradaCompra(
        idCompra: id,
        fecha: hoy,
        producto: producto,
        unidad: unidad,
        unidades: u,
        precioUnitario: pu);

    // egreso en caja
    final mv = CashMove(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fecha: hoy,
        tipo: 'Egreso',
        concepto: 'Compra $producto',
        monto: c.total);
    final movs = await cash.loadMoves()..add(mv);
    await cash.saveMoves(movs);

    unidadesCtrl.clear();
    precioCtrl.clear();
    setState(() {});
  }

  Future<void> _delete(Purchase c) async {
    // solo permitimos borrar si el lote no se usó
    final qtyLote = await inv.qtyDeLote(c.id);
    if (qtyLote == null) return;
    if ((qtyLote - c.unidades).abs() > 1e-9) {
      // ya se usó algo
      showDialog(
          context: context,
          builder: (_) => const AlertDialog(
                title: Text('No se puede borrar'),
                content: Text('Ese lote ya se utilizó en ventas.'),
              ));
      return;
    }

    // eliminar lote e ítem de compras
    await inv.eliminarLotePorId(c.id);
    compras.removeWhere((x) => x.id == c.id);
    await pRepo.save(compras);

    // revertimos el egreso (ingreso de anulación)
    final mv = CashMove(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fecha: dateFmt.format(DateTime.now()),
      tipo: 'Ingreso',
      concepto: 'Anulación compra ${c.producto}',
      monto: c.total,
    );
    final movs = await cash.loadMoves()..add(mv);
    await cash.saveMoves(movs);

    setState(() {});
  }

  double get total => compras.fold<double>(0, (p, c) => p + c.total);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Compras')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              runSpacing: 8,
              spacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: producto,
                    items: catalogoProductos
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setState(() => producto = v ?? producto),
                    decoration: const InputDecoration(labelText: 'Producto'),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: unidadesCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Unidades'),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: precioCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Precio unitario'),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: TextEditingController(text: unidad),
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    onChanged: (v) => unidad = v,
                  ),
                ),
                FilledButton(onPressed: _add, child: const Text('Agregar')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fecha: ${dateFmt.format(DateTime.now())}'),
                Text('Total: ${currency.format(total)}'),
              ],
            ),
          ),
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
                        title: Text('${c.producto} · ${c.unidades} ${c.unidad}'),
                        subtitle: Text(
                            'Fecha: ${c.fecha} · P.Unit: ${currency.format(c.precioUnit)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(currency.format(c.total)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(c),
                              tooltip: 'Borrar compra (si el lote no se usó)',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// =====================
///        VENTAS
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
      m[s.fecha] = (m[s.fecha] ?? 0) + s.ingreso;
    }
    return m;
  }

  Future<void> _nueva() async {
    final hoy = dateFmt.format(DateTime.now());
    final res = await showDialog<_VentaTmp>(
        context: context, builder: (_) => const _VentaDialog());
    if (res == null) return;

    // consumo FIFO
    final ar = await inv.consumirRecetaFIFO(recetaPorcion, res.porciones);
    if (!ar.ok) {
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Faltantes en inventario'),
                content: Text(ar.faltantes.join('\n')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'))
                ],
              ));
      return;
    }

    final sale = Sale(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fecha: hoy,
      porciones: res.porciones,
      precioUnit: res.precioUnit,
      costoMP: ar.costoMP,
      nota: res.nota,
    );
    sales.add(sale);
    await repo.save(sales);

    // ingreso en caja
    final mv = CashMove(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fecha: hoy,
        tipo: 'Ingreso',
        concepto: 'Venta ${sale.porciones.toStringAsFixed(0)} porciones',
        monto: sale.ingreso);
    final movs = await cash.loadMoves()..add(mv);
    await cash.saveMoves(movs);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sum = sales.fold<double>(0, (p, s) => p + s.ingreso);
    final grouped = resumenPorDia.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Ventas')),
      floatingActionButton:
          FloatingActionButton.extended(onPressed: _nueva, label: const Text('Venta'), icon: const Icon(Icons.add)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Registros: ${sales.length}'),
              Text('Acumulado: ${currency.format(sum)}'),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: grouped.isEmpty
              ? const Center(child: Text('Sin ventas'))
              : ListView.separated(
                  itemCount: grouped.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = grouped[i];
                    return ListTile(
                      title: Text(e.key),
                      trailing: Text(currency.format(e.value)),
                      onTap: () {
                        final det =
                            sales.where((s) => s.fecha == e.key).toList();
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
                                              'MP (PEPS): ${currency.format(s.costoMP)}  ·  MO: ${currency.format(s.costoMO)}  ·  GI: ${currency.format(s.costoGI)}'),
                                          trailing: Text(
                                              'Ganancia: ${currency.format(s.ganancia)}'),
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

class _VentaTmp {
  final double porciones, precioUnit;
  final String nota;
  _VentaTmp(this.porciones, this.precioUnit, this.nota);
}

class _VentaDialog extends StatefulWidget {
  const _VentaDialog();
  @override
  State<_VentaDialog> createState() => _VentaDialogState();
}

class _VentaDialogState extends State<_VentaDialog> {
  final porciones = TextEditingController();
  final precio = TextEditingController();
  final nota = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva venta'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Fecha: ${dateFmt.format(DateTime.now())}'),
        const SizedBox(height: 8),
        TextField(
            controller: porciones,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Porciones')),
        const SizedBox(height: 8),
        TextField(
            controller: precio,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio por porción')),
        const SizedBox(height: 8),
        TextField(controller: nota, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final p = double.tryParse(porciones.text.replaceAll(',', '.')) ?? 0;
              final u = double.tryParse(precio.text.replaceAll(',', '.')) ?? 0;
              Navigator.pop(context, _VentaTmp(p, u, nota.text.trim()));
            },
            child: const Text('Guardar')),
      ],
    );
  }
}

/// =====================
///         CAJA
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

  @override
  Widget build(BuildContext context) {
    final dif = ultimoArqueo == null ? null : (ultimoArqueo! - saldoTeorico);
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Caja')),
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
                child: Text('Diferencia: ${currency.format(dif)}')),
          ),
        const Divider(),
        Expanded(
          child: ListView(
            children: [
              const ListTile(title: Text('Movimientos')),
              if (moves.isEmpty)
                const ListTile(title: Text('— Sin movimientos —'))
              else
                ...moves.map((m) => ListTile(
                      leading: Icon(
                          m.tipo == 'Ingreso'
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          color:
                              m.tipo == 'Ingreso' ? Colors.green : Colors.red),
                      title: Text('${m.tipo} · ${currency.format(m.monto)}'),
                      subtitle: Text('${m.concepto}\n${m.fecha}'),
                      isThreeLine: true,
                    )),
              const Divider(),
              const ListTile(title: Text('Arqueos')),
              if (counts.isEmpty)
                const ListTile(title: Text('— Sin arqueos —'))
              else
                ...counts.map((c) => ListTile(
                      title:
                          Text('${c.fecha} · Contado: ${currency.format(c.total)}'),
                    )),
            ],
          ),
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              final mv = CashMove(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                fecha: hoy,
                tipo: tipo,
                concepto: concepto.text.trim(),
                monto: double.tryParse(monto.text.replaceAll(',', '.')) ?? 0.0,
              );
              Navigator.pop(context, mv);
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
                        onChanged: (_) => setState(() {}),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Total contado: ${currency.format(_calcTotal())}'),
          ),
        ]),
      ),
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
            child: const Text('Guardar')),
      ],
    );
  }
}

/// =====================
///   REPORTE DE COSTOS
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

  double get porcionesTotal =>
      filtered.fold<double>(0, (p, s) => p + s.porciones);
  double get ingresoTotal =>
      filtered.fold<double>(0, (p, s) => p + s.ingreso);
  double get costoMP =>
      filtered.fold<double>(0, (p, s) => p + s.costoMP);
  double get costoMO =>
      filtered.fold<double>(0, (p, s) => p + s.costoMO);
  double get costoGI =>
      filtered.fold<double>(0, (p, s) => p + s.costoGI);
  double get costoTotal => costoMP + costoMO + costoGI;
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
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Reporte de Costos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
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
          ]),
          const SizedBox(height: 12),
          _kv('Porciones vendidas', porcionesTotal.toStringAsFixed(0)),
          _kv('Ingresos', currency.format(ingresoTotal)),
          const Divider(),
          _kv('Materia prima (PEPS)', currency.format(costoMP)),
          _kv('Mano de obra', currency.format(costoMO)),
          _kv('Gastos indirectos', currency.format(costoGI)),
          _kv('Costo total', currency.format(costoTotal)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: gananciaNeta >= 0
                  ? Colors.green.withOpacity(.12)
                  : Colors.red.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _kv('GANANCIA NETA', currency.format(gananciaNeta), bold: true),
          ),
          const SizedBox(height: 12),
          const Text('Ventas del período',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...filtered.map((s) => ListTile(
                dense: true,
                title: Text('${s.fecha} · ${s.porciones.toStringAsFixed(0)} porciones'),
                subtitle: Text(
                    'P.Unit: ${currency.format(s.precioUnit)}  ·  MP(PEPS): ${currency.format(s.costoMP)}  ·  MO: ${currency.format(s.costoMO)}  ·  GI: ${currency.format(s.costoGI)}'),
                trailing: Text('G: ${currency.format(s.ganancia)}'),
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
