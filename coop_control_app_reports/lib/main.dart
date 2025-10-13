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

/// ===== Catálogo y Receta por porción =====
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

const double COSTO_MO = 3.57;
const double COSTO_GI = 1.67;

/// ===== Resultados de aplicar receta =====
class ApplyResult {
  final bool ok;
  final List<String> faltantes;
  final double costoMP; // costo de materia prima consumida (PEPS)
  const ApplyResult(this.ok, this.faltantes, this.costoMP);
}

/// ===== App =====
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
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NavCard(
            'Inventario (PEPS)',
            'Resumen por producto con lotes FIFO',
            Icons.inventory_2_outlined,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryScreen())),
          ),
          _NavCard(
            'Compras',
            'Entradas al inventario (crea lotes PEPS)',
            Icons.shopping_cart_outlined,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseScreen())),
          ),
          _NavCard(
            'Ventas',
            'Registra porciones (descuenta PEPS)',
            Icons.point_of_sale_outlined,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesScreen())),
          ),
          _NavCard(
            'Caja',
            'Ingresos/Egresos y Arqueo',
            Icons.account_balance_wallet,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashScreen())),
          ),
          _NavCard(
            'Reporte de Costos',
            'MP(PEPS)+MO+GI y Ganancia neta',
            Icons.bar_chart,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CostReportScreen())),
          ),
        ],
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
      margin: const EdgeInsets.only(bottom: 10),
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

/// Lote PEPS
class InventoryLot {
  final String id; // id compra
  final String fecha;
  final String producto;
  final String unidad;
  final double precioUnit;
  final double qty;

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
        unidad: j['unidad'] ?? 'unidad',
        precioUnit: (j['precioUnit'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
      );
}

class InvResumen {
  final String producto, unidad;
  final double cantidad, valor, precioPromedio;
  const InvResumen(this.producto, this.unidad, this.cantidad, this.valor, this.precioPromedio);
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
    await p.setString(_lotsKey, jsonEncode(lots.map((e) => e.toJson()).toList()));
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

  Future<List<InvResumen>> resumen() async {
    final lots = await _loadLots();
    final Map<String, List<InventoryLot>> byProd = {};
    for (final l in lots) {
      byProd.putIfAbsent(_norm(l.producto), () => []).add(l);
    }
    final out = <InvResumen>[];
    byProd.forEach((_, ls) {
      final nombre = ls.first.producto;
      final unidad = ls.first.unidad;
      final cant = ls.fold<double>(0, (p, l) => p + l.qty);
      final val = ls.fold<double>(0, (p, l) => p + l.qty * l.precioUnit);
      final prom = cant > 0 ? val / cant : 0;
      out.add(InvResumen(nombre, unidad, cant, val, prom));
    });
    out.sort((a, b) => a.producto.compareTo(b.producto));
    return out;
  }

  /// Consumir receta por PEPS; devuelve costo MP usado.
  Future<ApplyResult> consumirRecetaFIFO(Map<String, double> receta, double porciones) async {
    final lots = await _loadLots();

    // Verificar faltantes
    final need = {for (final e in receta.entries) e.key: e.value * porciones};
    final faltantes = <String>[];
    for (final e in need.entries) {
      final disp = lots.where((l) => _norm(l.producto) == e.key).fold<double>(0, (p, l) => p + l.qty);
      if (disp + 1e-9 < e.value) {
        faltantes.add('${e.key.toUpperCase()}: falta ${(e.value - disp).toStringAsFixed(3)}');
      }
    }
    if (faltantes.isNotEmpty) return ApplyResult(false, faltantes, 0);

    // Descontar FIFO
    double costoMP = 0;
    for (final e in need.entries) {
      double req = e.value;
      final fifo = lots.where((l) => _norm(l.producto) == e.key).toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
      for (final l in fifo) {
        if (req <= 0) break;
        final take = req <= l.qty ? req : l.qty;
        costoMP += take * l.precioUnit;
        final idx = lots.indexWhere((x) => x.id == l.id);
        lots[idx] = InventoryLot(
          id: l.id, fecha: l.fecha, producto: l.producto, unidad: l.unidad,
          precioUnit: l.precioUnit, qty: l.qty - take,
        );
        req -= take;
      }
    }
    await _saveLots(lots);
    return ApplyResult(true, const [], costoMP);
  }

  Future<void> eliminarLotePorId(String lotId) async {
    final lots = await _loadLots();
    lots.removeWhere((l) => l.id == lotId);
    await _saveLots(lots);
  }

  Future<double?> qtyDeLote(String lotId) async {
    final lots = await _loadLots();
    final f = lots.where((e) => e.id == lotId).toList();
    if (f.isEmpty) return null;
    return f.first.qty;
  }
}

/// Compra
class Purchase {
  final String id, fecha, producto, unidad;
  final double unidades, precioUnit;
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

/// Venta (guardamos costo MP PEPS calculado)
class Sale {
  final String id, fecha, nota;
  final double porciones, precioUnit, costoMP;
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
  final String id, fecha, tipo, concepto;
  final double monto;
  const CashMove({required this.id, required this.fecha, required this.tipo, required this.concepto, required this.monto});
  Map<String, dynamic> toJson()=>{'id':id,'fecha':fecha,'tipo':tipo,'concepto':concepto,'monto':monto};
  factory CashMove.fromJson(Map<String,dynamic> j)=>CashMove(id:j['id'],fecha:j['fecha'],tipo:j['tipo'],concepto:j['concepto'],monto:(j['monto'] as num).toDouble());
}
class CashCount {
  final String id, fecha; final Map<String,int> denom;
  const CashCount({required this.id, required this.fecha, required this.denom});
  double get total => 200*(denom['200']??0)+100*(denom['100']??0)+50*(denom['50']??0)+20*(denom['20']??0)+10*(denom['10']??0)+5*(denom['5']??0)+1*(denom['1']??0)+0.50*(denom['0.50']??0)+0.25*(denom['0.25']??0);
  Map<String,dynamic> toJson()=>{'id':id,'fecha':fecha,'denom':denom};
  factory CashCount.fromJson(Map<String,dynamic> j)=>CashCount(id:j['id'],fecha:j['fecha'],denom:(j['denom'] as Map).map((k,v)=>MapEntry(k.toString(), (v as num).toInt())));
}
class CashRepo {
  static const _mk='caja_movs_v1', _ck='caja_counts_v1';
  Future<List<CashMove>> loadMoves() async { final p=await SharedPreferences.getInstance(); final raw=p.getString(_mk); if(raw==null||raw.isEmpty)return[]; final list=(jsonDecode(raw) as List).cast<Map<String,dynamic>>(); return list.map(CashMove.fromJson).toList();}
  Future<void> saveMoves(List<CashMove> m) async { final p=await SharedPreferences.getInstance(); await p.setString(_mk, jsonEncode(m.map((e)=>e.toJson()).toList())); }
  Future<List<CashCount>> loadCounts() async { final p=await SharedPreferences.getInstance(); final raw=p.getString(_ck); if(raw==null||raw.isEmpty)return[]; final list=(jsonDecode(raw) as List).cast<Map<String,dynamic>>(); return list.map(CashCount.fromJson).toList();}
  Future<void> saveCounts(List<CashCount> c) async { final p=await SharedPreferences.getInstance(); await p.setString(_ck, jsonEncode(c.map((e)=>e.toJson()).toList())); }
}

/// =====================
///     INVENTARIO
/// =====================

class InventoryScreen extends StatefulWidget { const InventoryScreen({super.key}); @override State<InventoryScreen> createState()=>_InventoryScreenState(); }
class _InventoryScreenState extends State<InventoryScreen> {
  final inv = InventoryRepo(); List<InvResumen> data=[];
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { data = await inv.resumen(); setState((){}); }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Producto','Unidad','Existencia','P.Promedio','Valor'];
    final rows = data.map((r)=>[r.producto,r.unidad,r.cantidad.toStringAsFixed(2),currency.format(r.precioPromedio),currency.format(r.valor)]).toList();
    final total = data.fold<double>(0,(p,r)=>p+r.valor);
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Inventario (PEPS)', style: pw.TextStyle(fontSize:20))),
      pw.Text('Fecha: ${dateFmt.format(DateTime.now())}'),
      pw.SizedBox(height:8),
      pw.Table.fromTextArray(headers: headers, data: rows),
      pw.SizedBox(height:8),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Valor total: ${currency.format(total)}')),
    ]));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'inventario_peps.pdf');
  }

  // Convierte cualquier lista en Strings para Excel (evita errores de tipos).
  List<dynamic> _xs(List<dynamic> row) => row.map((e){
    if (e is num) return e.toString();
    return e?.toString() ?? '';
  }).toList();

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final sh = excel['Inventario'];
    sh.appendRow(_xs(['Producto','Unidad','Existencia','P.Promedio','Valor']));
    for(final r in data){
      sh.appendRow(_xs([r.producto,r.unidad,r.cantidad,r.precioPromedio,r.valor]));
    }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/inventario_peps.xlsx';
    await File(path).writeAsBytes(bytes, flush:true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context){
    final total = data.fold<double>(0,(p,r)=>p+r.valor);
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Inventario (PEPS)'), actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        PopupMenuButton<String>(onSelected:(v){ if(v=='pdf')_exportPdf(); if(v=='xlsx')_exportExcel(); }, itemBuilder:(_)=>const [
          PopupMenuItem(value:'pdf', child: Text('Exportar PDF')),
          PopupMenuItem(value:'xlsx', child: Text('Exportar Excel')),
        ])
      ]),
      body: data.isEmpty? const Center(child: Text('Sin existencias')) :
        ListView.separated(itemCount: data.length, separatorBuilder: (_,__)=>
          const Divider(height:1), itemBuilder: (_ ,i){
            final r=data[i];
            return ListTile(
              title: Text(r.producto),
              subtitle: Text('Unidad: ${r.unidad} · P.Promedio: ${currency.format(r.precioPromedio)}'),
              trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children:[
                Text('Existencia: ${r.cantidad.toStringAsFixed(2)}'),
                Text(currency.format(r.valor)),
              ]),
            );
          }),
      bottomNavigationBar: Padding(padding: const EdgeInsets.all(12), child: Text('Valor total: ${currency.format(total)}', textAlign: TextAlign.right)),
    );
  }
}

/// =====================
///       COMPRAS
/// =====================

class PurchaseScreen extends StatefulWidget { const PurchaseScreen({super.key}); @override State<PurchaseScreen> createState()=>_PurchaseScreenState(); }
class _PurchaseScreenState extends State<PurchaseScreen> {
  final pRepo = PurchaseRepo(); final inv = InventoryRepo(); final cash = CashRepo();
  String producto = catalogoProductos.first; String unidad='unidad';
  final unidadesCtrl=TextEditingController(); final precioCtrl=TextEditingController();
  List<Purchase> compras=[];

  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { compras=await pRepo.load(); setState((){}); }

  Future<void> _add() async {
    final hoy = dateFmt.format(DateTime.now());
    final u = double.tryParse(unidadesCtrl.text.replaceAll(',', '.')) ?? 0;
    final pu = double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 0;
    if (u<=0 || pu<=0) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final c = Purchase(id:id, fecha:hoy, producto:producto, unidad:unidad, unidades:u, precioUnit:pu);
    compras.add(c); await pRepo.save(compras);
    await inv.entradaCompra(idCompra:id, fecha:hoy, producto:producto, unidad:unidad, unidades:u, precioUnitario:pu);
    final mv = CashMove(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: hoy, tipo:'Egreso', concepto:'Compra $producto', monto:c.total);
    final movs = await cash.loadMoves()..add(mv); await cash.saveMoves(movs);
    unidadesCtrl.clear(); precioCtrl.clear(); setState((){});
  }

  Future<void> _delete(Purchase c) async {
    final qtyLote = await inv.qtyDeLote(c.id);
    if (qtyLote == null) return;
    if ((qtyLote - c.unidades).abs() > 1e-9) {
      showDialog(context: context, builder: (_)=>const AlertDialog(title: Text('No se puede borrar'), content: Text('Ese lote ya se utilizó en ventas.')));
      return;
    }
    await inv.eliminarLotePorId(c.id);
    compras.removeWhere((x)=>x.id==c.id);
    await pRepo.save(compras);
    final mv = CashMove(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: dateFmt.format(DateTime.now()), tipo:'Ingreso', concepto:'Anulación compra ${c.producto}', monto:c.total);
    final movs = await cash.loadMoves()..add(mv); await cash.saveMoves(movs);
    setState((){});
  }

  double get total => compras.fold<double>(0,(p,c)=>p+c.total);

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers=['Fecha','Producto','Unidad','Unidades','P.Unit','Total'];
    final rows = compras.map((c)=>[c.fecha,c.producto,c.unidad,c.unidades.toStringAsFixed(3),currency.format(c.precioUnit),currency.format(c.total)]).toList();
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Compras', style: pw.TextStyle(fontSize:20))),
      pw.Text('Generado: ${dateFmt.format(DateTime.now())}'),
      pw.SizedBox(height:8),
      pw.Table.fromTextArray(headers: headers, data: rows),
      pw.SizedBox(height:8),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Total: ${currency.format(total)}')),
    ]));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'compras.pdf');
  }

  List<dynamic> _xs(List<dynamic> row) => row.map((e)=> (e is num)? e.toString() : (e?.toString() ?? '')).toList();
  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel(); final sh=excel['Compras'];
    sh.appendRow(_xs(['Fecha','Producto','Unidad','Unidades','P.Unit','Total']));
    for(final c in compras){ sh.appendRow(_xs([c.fecha,c.producto,c.unidad,c.unidades,c.precioUnit,c.total])); }
    final bytes=excel.encode()!; final dir=await getTemporaryDirectory(); final path='${dir.path}/compras.xlsx'; await File(path).writeAsBytes(bytes, flush:true); await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Compras'), actions:[
        PopupMenuButton<String>(onSelected:(v){ if(v=='pdf')_exportPdf(); if(v=='xlsx')_exportExcel(); }, itemBuilder:(_)=>const [
          PopupMenuItem(value:'pdf', child: Text('Exportar PDF')),
          PopupMenuItem(value:'xlsx', child: Text('Exportar Excel')),
        ])
      ]),
      body: Column(children:[
        Padding(padding: const EdgeInsets.all(12), child: Wrap(runSpacing:8, spacing:8, children:[
          SizedBox(width:220, child: DropdownButtonFormField<String>(value:producto, items: catalogoProductos.map((p)=>DropdownMenuItem(value:p, child: Text(p))).toList(), onChanged:(v)=>setState(()=>producto=v??producto), decoration: const InputDecoration(labelText:'Producto'))),
          SizedBox(width:140, child: TextField(controller:unidadesCtrl, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Unidades'))),
          SizedBox(width:140, child: TextField(controller:precioCtrl, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Precio unitario'))),
          SizedBox(width:140, child: TextField(controller: TextEditingController(text:unidad), decoration: const InputDecoration(labelText:'Unidad'), onChanged:(v)=>unidad=v)),
          FilledButton(onPressed:_add, child: const Text('Agregar')),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal:12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
          Text('Fecha: ${dateFmt.format(DateTime.now())}'),
          Text('Total: ${currency.format(total)}'),
        ])),
        const Divider(),
        Expanded(child: compras.isEmpty? const Center(child: Text('Sin compras')) :
          ListView.separated(itemCount: compras.length, separatorBuilder: (_,__)=>
            const Divider(height:1), itemBuilder: (_ ,i){
              final c=compras[compras.length-1-i];
              return ListTile(
                title: Text('${c.producto} · ${c.unidades} ${c.unidad}'),
                subtitle: Text('Fecha: ${c.fecha} · P.Unit: ${currency.format(c.precioUnit)}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children:[
                  Text(currency.format(c.total)),
                  IconButton(icon: const Icon(Icons.delete_outline), tooltip:'Borrar compra (si lote no se usó)', onPressed: ()=>_delete(c)),
                ]),
              );
            })
        ),
      ]),
    );
  }
}

/// =====================
///        VENTAS
/// =====================

class SalesScreen extends StatefulWidget { const SalesScreen({super.key}); @override State<SalesScreen> createState()=>_SalesScreenState(); }
class _SalesScreenState extends State<SalesScreen>{
  final repo=SalesRepo(); final inv=InventoryRepo(); final cash=CashRepo(); List<Sale> sales=[];
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { sales=await repo.load(); setState((){}); }

  Map<String,double> get resumenPorDia { final m=<String,double>{}; for(final s in sales){ m[s.fecha]=(m[s.fecha]??0)+s.ingreso; } return m; }

  Future<void> _nueva() async {
    final hoy=dateFmt.format(DateTime.now());
    final res=await showDialog<_VentaTmp>(context: context, builder: (_)=>const _VentaDialog());
    if(res==null) return;
    final ar=await inv.consumirRecetaFIFO(recetaPorcion, res.porciones);
    if(!ar.ok){
      showDialog(context: context, builder: (_)=>AlertDialog(title: const Text('Faltantes en inventario'), content: Text(ar.faltantes.join('\n')), actions:[TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cerrar'))]));
      return;
    }
    final sale = Sale(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: hoy, porciones: res.porciones, precioUnit: res.precioUnit, costoMP: ar.costoMP, nota: res.nota);
    sales.add(sale); await repo.save(sales);
    final mv = CashMove(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: hoy, tipo:'Ingreso', concepto:'Venta ${sale.porciones.toStringAsFixed(0)} porciones', monto: sale.ingreso);
    final movs = await cash.loadMoves()..add(mv); await cash.saveMoves(movs);
    setState((){});
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers=['Fecha','Porciones','P.Unit','Ingreso','MP(PEPS)','MO','GI','Ganancia','Nota'];
    final rows = sales.map((s)=>[s.fecha,s.porciones.toStringAsFixed(0),currency.format(s.precioUnit),currency.format(s.ingreso),currency.format(s.costoMP),currency.format(s.costoMO),currency.format(s.costoGI),currency.format(s.ganancia),s.nota]).toList();
    final byDay = resumenPorDia.entries.toList()..sort((a,b)=>b.key.compareTo(a.key));
    final sum = sales.fold<double>(0,(p,s)=>p+s.ingreso);
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Ventas', style: pw.TextStyle(fontSize:20))),
      pw.Text('Generado: ${dateFmt.format(DateTime.now())}  ·  Total ingresos: ${currency.format(sum)}'),
      pw.SizedBox(height:8),
      pw.Text('Resumen por día'),
      pw.Table.fromTextArray(headers: ['Día','Total'], data: byDay.map((e)=>[e.key, currency.format(e.value)]).toList()),
      pw.SizedBox(height:8),
      pw.Text('Detalle'),
      pw.Table.fromTextArray(headers: headers, data: rows),
    ]));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'ventas.pdf');
  }

  List<dynamic> _xs(List<dynamic> row) => row.map((e)=> (e is num)? e.toString() : (e?.toString() ?? '')).toList();
  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1 = excel['Ventas'];
    s1.appendRow(_xs(['Fecha','Porciones','P.Unit','Ingreso','MP(PEPS)','MO','GI','Ganancia','Nota']));
    for(final s in sales){
      s1.appendRow(_xs([s.fecha,s.porciones,s.precioUnit,s.ingreso,s.costoMP,s.costoMO,s.costoGI,s.ganancia,s.nota]));
    }
    final s2 = excel['Resumen_por_dia'];
    s2.appendRow(_xs(['Día','Total']));
    resumenPorDia.forEach((k,v)=> s2.appendRow(_xs([k,v])));
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ventas.xlsx';
    await File(path).writeAsBytes(bytes, flush:true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context){
    final sum = sales.fold<double>(0,(p,s)=>p+s.ingreso);
    final grouped = resumenPorDia.entries.toList()..sort((a,b)=>b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Ventas'), actions:[
        PopupMenuButton<String>(onSelected:(v){ if(v=='pdf')_exportPdf(); if(v=='xlsx')_exportExcel(); }, itemBuilder:(_)=>const [
          PopupMenuItem(value:'pdf', child: Text('Exportar PDF')),
          PopupMenuItem(value:'xlsx', child: Text('Exportar Excel')),
        ])
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed:_nueva, icon: const Icon(Icons.add), label: const Text('Venta')),
      body: Column(children:[
        Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
          Text('Registros: ${sales.length}'),
          Text('Acumulado: ${currency.format(sum)}'),
        ])),
        const Divider(),
        Expanded(child: grouped.isEmpty ? const Center(child: Text('Sin ventas')) :
          ListView.separated(itemCount: grouped.length, separatorBuilder: (_,__)=>
            const Divider(height:1), itemBuilder: (_ ,i){
              final e=grouped[i];
              return ListTile(
                title: Text(e.key),
                trailing: Text(currency.format(e.value)),
                onTap: (){
                  final det = sales.where((s)=>s.fecha==e.key).toList();
                  showModalBottomSheet(context: context, showDragHandle: true, builder: (_)=>ListView(padding: const EdgeInsets.all(12), children:[
                    Text('Detalle del ${e.key}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height:8),
                    ...det.map((s)=>ListTile(
                      title: Text('${s.porciones.toStringAsFixed(0)} porciones · ${currency.format(s.ingreso)}'),
                      subtitle: Text('MP(PEPS): ${currency.format(s.costoMP)} · MO: ${currency.format(s.costoMO)} · GI: ${currency.format(s.costoGI)}'),
                      trailing: Text('G: ${currency.format(s.ganancia)}'),
                    )),
                  ]));
                },
              );
            })
        ),
      ]),
    );
  }
}

class _VentaTmp { final double porciones, precioUnit; final String nota; _VentaTmp(this.porciones, this.precioUnit, this.nota); }
class _VentaDialog extends StatefulWidget { const _VentaDialog(); @override State<_VentaDialog> createState()=>_VentaDialogState(); }
class _VentaDialogState extends State<_VentaDialog>{
  final porciones=TextEditingController(); final precio=TextEditingController(); final nota=TextEditingController();
  @override Widget build(BuildContext context){
    return AlertDialog(title: const Text('Nueva venta'), content: Column(mainAxisSize: MainAxisSize.min, children:[
      Text('Fecha: ${dateFmt.format(DateTime.now())}'),
      const SizedBox(height:8),
      TextField(controller:porciones, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Porciones')),
      const SizedBox(height:8),
      TextField(controller:precio, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Precio por porción')),
      const SizedBox(height:8),
      TextField(controller:nota, decoration: const InputDecoration(labelText:'Nota (opcional)')),
    ]), actions:[
      TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: (){
        final p=double.tryParse(porciones.text.replaceAll(',', '.'))??0;
        final u=double.tryParse(precio.text.replaceAll(',', '.'))??0;
        Navigator.pop(context, _VentaTmp(p,u,nota.text.trim()));
      }, child: const Text('Guardar')),
    ]);
  }
}

/// =====================
///         CAJA
/// =====================

class CashScreen extends StatefulWidget { const CashScreen({super.key}); @override State<CashScreen> createState()=>_CashScreenState(); }
class _CashScreenState extends State<CashScreen>{
  final repo=CashRepo(); List<CashMove> moves=[]; List<CashCount> counts=[];
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { moves=await repo.loadMoves(); counts=await repo.loadCounts(); setState((){}); }
  double get saldoTeorico { final ing=moves.where((m)=>m.tipo=='Ingreso').fold<double>(0,(p,m)=>p+m.monto); final egr=moves.where((m)=>m.tipo=='Egreso').fold<double>(0,(p,m)=>p+m.monto); return ing-egr; }
  double? get ultimoArqueo { if(counts.isEmpty) return null; counts.sort((a,b)=>b.fecha.compareTo(a.fecha)); return counts.first.total; }
  Future<void> _addMove() async { final res=await showDialog<CashMove>(context: context, builder: (_)=>const _MoveDialog()); if(res!=null){ moves.add(res); await repo.saveMoves(moves); setState((){});} }
  Future<void> _addCount() async { final res=await showDialog<CashCount>(context: context, builder: (_)=>const _CountDialog()); if(res!=null){ counts.add(res); await repo.saveCounts(counts); setState((){});} }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final mh=['Fecha','Tipo','Concepto','Monto'];
    final mrows=moves.map((m)=>[m.fecha,m.tipo,m.concepto,currency.format(m.monto)]).toList();
    final ch=['Fecha','Q200','Q100','Q50','Q20','Q10','Q5','Q1','Q0.50','Q0.25','Total'];
    final crows=counts.map((c)=>[c.fecha,c.denom['200']??0,c.denom['100']??0,c.denom['50']??0,c.denom['20']??0,c.denom['10']??0,c.denom['5']??0,c.denom['1']??0,c.denom['0.50']??0,c.denom['0.25']??0,currency.format(c.total)]).toList();
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Caja', style: pw.TextStyle(fontSize:20))),
      pw.Text('Generado: ${dateFmt.format(DateTime.now())}'),
      pw.SizedBox(height:8),
      pw.Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
      pw.Text('Último arqueo: ${ultimoArqueo==null?'-':currency.format(ultimoArqueo!)}'),
      if(ultimoArqueo!=null) pw.Text('Diferencia: ${currency.format(ultimoArqueo!-saldoTeorico)}'),
      pw.SizedBox(height:8),
      pw.Text('Movimientos'),
      pw.Table.fromTextArray(headers: mh, data: mrows),
      pw.SizedBox(height:8),
      pw.Text('Arqueos'),
      pw.Table.fromTextArray(headers: ch, data: crows),
    ]));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'caja.pdf');
  }

  List<dynamic> _xs(List<dynamic> row) => row.map((e)=> (e is num)? e.toString() : (e?.toString() ?? '')).toList();
  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1=excel['Caja_Movimientos']; s1.appendRow(_xs(['Fecha','Tipo','Concepto','Monto']));
    for(final m in moves){ s1.appendRow(_xs([m.fecha,m.tipo,m.concepto,m.monto])); }
    final s2=excel['Caja_Arqueos']; s2.appendRow(_xs(['Fecha','Q200','Q100','Q50','Q20','Q10','Q5','Q1','Q0.50','Q0.25','Total']));
    for(final c in counts){ s2.appendRow(_xs([c.fecha,c.denom['200']??0,c.denom['100']??0,c.denom['50']??0,c.denom['20']??0,c.denom['10']??0,c.denom['5']??0,c.denom['1']??0,c.denom['0.50']??0,c.denom['0.25']??0,c.total])); }
    final bytes=excel.encode()!; final dir=await getTemporaryDirectory(); final path='${dir.path}/caja.xlsx'; await File(path).writeAsBytes(bytes, flush:true); await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context){
    final dif = ultimoArqueo==null? null : (ultimoArqueo!-saldoTeorico);
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Caja'), actions:[
        PopupMenuButton<String>(onSelected:(v){ if(v=='pdf')_exportPdf(); if(v=='xlsx')_exportExcel(); }, itemBuilder:(_)=>const [
          PopupMenuItem(value:'pdf', child: Text('Exportar PDF')),
          PopupMenuItem(value:'xlsx', child: Text('Exportar Excel')),
        ])
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children:[
        FloatingActionButton.extended(heroTag:'m1', onPressed:_addMove, icon: const Icon(Icons.swap_vert), label: const Text('Movimiento')),
        const SizedBox(height:8),
        FloatingActionButton.extended(heroTag:'m2', onPressed:_addCount, icon: const Icon(Icons.calculate_outlined), label: const Text('Arqueo')),
      ]),
      body: Column(children:[
        Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
          Text('Saldo teórico: ${currency.format(saldoTeorico)}'),
          Text(ultimoArqueo==null? 'Sin arqueo' : 'Último arqueo: ${currency.format(ultimoArqueo)}'),
        ])),
        if(dif!=null) Padding(padding: const EdgeInsets.symmetric(horizontal:12), child: Align(alignment: Alignment.centerLeft, child: Text('Diferencia: ${currency.format(dif)}'))),
        const Divider(),
        Expanded(child: ListView(children:[
          const ListTile(title: Text('Movimientos')),
          if(moves.isEmpty) const ListTile(title: Text('— Sin movimientos —')) else ...moves.map((m)=>ListTile(
            leading: Icon(m.tipo=='Ingreso'? Icons.arrow_downward : Icons.arrow_upward, color: m.tipo=='Ingreso'? Colors.green : Colors.red),
            title: Text('${m.tipo} · ${currency.format(m.monto)}'),
            subtitle: Text('${m.concepto}\n${m.fecha}'), isThreeLine: true,
          )),
          const Divider(),
          const ListTile(title: Text('Arqueos')),
          if(counts.isEmpty) const ListTile(title: Text('— Sin arqueos —')) else ...counts.map((c)=>ListTile(
            title: Text('${c.fecha} · Contado: ${currency.format(c.total)}'),
          )),
        ])),
      ]),
    );
  }
}
class _MoveDialog extends StatefulWidget { const _MoveDialog(); @override State<_MoveDialog> createState()=>_MoveDialogState(); }
class _MoveDialogState extends State<_MoveDialog>{
  String tipo='Ingreso'; final concepto=TextEditingController(); final monto=TextEditingController();
  @override Widget build(BuildContext context){
    final hoy=dateFmt.format(DateTime.now());
    return AlertDialog(title: const Text('Nuevo movimiento'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children:[
      DropdownButtonFormField<String>(value: tipo, items: const [DropdownMenuItem(value:'Ingreso', child: Text('Ingreso')), DropdownMenuItem(value:'Egreso', child: Text('Egreso'))], onChanged:(v)=>setState(()=>tipo=v??'Ingreso'), decoration: const InputDecoration(labelText:'Tipo')),
      const SizedBox(height:8),
      TextField(controller: concepto, decoration: const InputDecoration(labelText:'Concepto')),
      const SizedBox(height:8),
      TextField(controller:monto, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Monto')),
    ])), actions:[
      TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: (){
        final mv = CashMove(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: hoy, tipo: tipo, concepto: concepto.text.trim(), monto: double.tryParse(monto.text.replaceAll(',', '.')) ?? 0.0);
        Navigator.pop(context, mv);
      }, child: const Text('Guardar')),
    ]);
  }
}
class _CountDialog extends StatefulWidget { const _CountDialog(); @override State<_CountDialog> createState()=>_CountDialogState(); }
class _CountDialogState extends State<_CountDialog>{
  final Map<String, TextEditingController> ctrl = {'200':TextEditingController(text:'0'),'100':TextEditingController(text:'0'),'50':TextEditingController(text:'0'),'20':TextEditingController(text:'0'),'10':TextEditingController(text:'0'),'5':TextEditingController(text:'0'),'1':TextEditingController(text:'0'),'0.50':TextEditingController(text:'0'),'0.25':TextEditingController(text:'0')};
  double _calcTotal(){ double t=0; ctrl.forEach((k,v){ final c=int.tryParse(v.text)??0; final val=double.parse(k); t+=c*val; }); return t; }
  @override Widget build(BuildContext context){
    final hoy=dateFmt.format(DateTime.now());
    return AlertDialog(title: const Text('Arqueo de caja'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children:[
      Wrap(spacing:8, runSpacing:8, children: ctrl.keys.map((k)=>SizedBox(width:100, child: TextField(controller: ctrl[k], keyboardType: TextInputType.number, decoration: InputDecoration(labelText:'Q $k'), onChanged: (_)=>setState((){})))).toList()),
      const SizedBox(height:8),
      Align(alignment: Alignment.centerLeft, child: Text('Total contado: ${currency.format(_calcTotal())}')),
    ])), actions:[
      TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: (){ final denom={for(final e in ctrl.entries) e.key: int.tryParse(e.value.text) ?? 0}; final cc=CashCount(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: hoy, denom: denom); Navigator.pop(context, cc); }, child: const Text('Guardar'))
    ]);
  }
}

/// =====================
///   REPORTE DE COSTOS
/// =====================

class CostReportScreen extends StatefulWidget { const CostReportScreen({super.key}); @override State<CostReportScreen> createState()=>_CostReportScreenState(); }
class _CostReportScreenState extends State<CostReportScreen>{
  final sRepo=SalesRepo(); List<Sale> all=[]; DateTime from=DateTime.now().subtract(const Duration(days:6)); DateTime to=DateTime.now();
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { all=await sRepo.load(); setState((){}); }
  List<Sale> get filtered { return all.where((s){ final d=DateTime.parse(s.fecha); final a=DateTime(from.year,from.month,from.day); final b=DateTime(to.year,to.month,to.day,23,59,59); return !d.isBefore(a) && !d.isAfter(b); }).toList(); }
  double get porcionesTotal=>filtered.fold<double>(0,(p,s)=>p+s.porciones);
  double get ingresoTotal=>filtered.fold<double>(0,(p,s)=>p+s.ingreso);
  double get costoMP=>filtered.fold<double>(0,(p,s)=>p+s.costoMP);
  double get costoMO=>filtered.fold<double>(0,(p,s)=>p+s.costoMO);
  double get costoGI=>filtered.fold<double>(0,(p,s)=>p+s.costoGI);
  double get costoTotal=>costoMP+costoMO+costoGI;
  double get gananciaNeta=>ingresoTotal-costoTotal;

  Future<void> _exportPdf() async {
    final pdf=pw.Document();
    final headers=['Fecha','Porciones','Ingreso','MP(PEPS)','MO','GI','Costo Total','Ganancia'];
    final rows=filtered.map((s)=>[s.fecha,s.porciones.toStringAsFixed(0),currency.format(s.ingreso),currency.format(s.costoMP),currency.format(s.costoMO),currency.format(s.costoGI),currency.format(s.costoTotal),currency.format(s.ganancia)]).toList();
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Reporte de Costos', style: pw.TextStyle(fontSize:20))),
      pw.Text('Período: ${dateFmt.format(from)} a ${dateFmt.format(to)}'),
      pw.SizedBox(height:8),
      pw.Table.fromTextArray(headers: headers, data: rows),
      pw.SizedBox(height:8),
      pw.Text('— Totales —'),
      pw.Bullet(text: 'Porciones: ${porcionesTotal.toStringAsFixed(0)}'),
      pw.Bullet(text: 'Ingresos: ${currency.format(ingresoTotal)}'),
      pw.Bullet(text: 'MP(PEPS): ${currency.format(costoMP)}'),
      pw.Bullet(text: 'MO: ${currency.format(costoMO)}'),
      pw.Bullet(text: 'GI: ${currency.format(costoGI)}'),
      pw.Bullet(text: 'Costo total: ${currency.format(costoTotal)}'),
      pw.Bullet(text: 'Ganancia neta: ${currency.format(gananciaNeta)}'),
    ]));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'reporte_costos.pdf');
  }

  List<dynamic> _xs(List<dynamic> row) => row.map((e)=> (e is num)? e.toString() : (e?.toString() ?? '')).toList();
  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1=excel['Resumen'];
    s1.appendRow(_xs(['Porciones','Ingresos','MP(PEPS)','MO','GI','Costo total','Ganancia neta']));
    s1.appendRow(_xs([porcionesTotal,ingresoTotal,costoMP,costoMO,costoGI,costoTotal,gananciaNeta]));
    final s2=excel['Ventas_detalle'];
    s2.appendRow(_xs(['Fecha','Porciones','Ingreso','MP(PEPS)','MO','GI','Costo Total','Ganancia']));
    for(final s in filtered){ s2.appendRow(_xs([s.fecha,s.porciones,s.ingreso,s.costoMP,s.costoMO,s.costoGI,s.costoTotal,s.ganancia])); }
    final bytes=excel.encode()!; final dir=await getTemporaryDirectory(); final path='${dir.path}/reporte_costos.xlsx'; await File(path).writeAsBytes(bytes, flush:true); await Share.shareXFiles([XFile(path)]);
  }

  Future<void> pickFrom() async { final d=await showDatePicker(context: context, initialDate: from, firstDate: DateTime(2023), lastDate: DateTime(2100)); if(d!=null) setState(()=>from=d); }
  Future<void> pickTo() async { final d=await showDatePicker(context: context, initialDate: to, firstDate: DateTime(2023), lastDate: DateTime(2100)); if(d!=null) setState(()=>to=d); }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('CONTROL ESQUITES — Reporte de Costos'), actions:[
        PopupMenuButton<String>(onSelected:(v){ if(v=='pdf')_exportPdf(); if(v=='xlsx')_exportExcel(); }, itemBuilder:(_)=>const [
          PopupMenuItem(value:'pdf', child: Text('Exportar PDF')),
          PopupMenuItem(value:'xlsx', child: Text('Exportar Excel')),
        ])
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children:[
        Row(children:[
          Expanded(child: OutlinedButton.icon(onPressed: pickFrom, icon: const Icon(Icons.date_range), label: Text('Desde: ${dateFmt.format(from)}'))),
          const SizedBox(width:8),
          Expanded(child: OutlinedButton.icon(onPressed: pickTo, icon: const Icon(Icons.date_range), label: Text('Hasta: ${dateFmt.format(to)}'))),
        ]),
        const SizedBox(height:12),
        _kv('Porciones vendidas', porcionesTotal.toStringAsFixed(0)),
        _kv('Ingresos', currency.format(ingresoTotal)),
        const Divider(),
        _kv('Materia prima (PEPS)', currency.format(costoMP)),
        _kv('Mano de obra', currency.format(costoMO)),
        _kv('Gastos indirectos', currency.format(costoGI)),
        _kv('Costo total', currency.format(costoTotal)),
        const SizedBox(height:12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: (gananciaNeta>=0? Colors.green : Colors.red).withOpacity(.12), borderRadius: BorderRadius.circular(12)),
          child: _kv('GANANCIA NETA', currency.format(gananciaNeta), bold:true),
        ),
        const SizedBox(height:12),
        const Text('Ventas del período', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height:8),
        ...filtered.map((s)=>ListTile(
          dense:true,
          title: Text('${s.fecha} · ${s.porciones.toStringAsFixed(0)} porciones'),
          subtitle: Text('P.Unit: ${currency.format(s.precioUnit)}  ·  MP(PEPS): ${currency.format(s.costoMP)}  ·  MO: ${currency.format(s.costoMO)}  ·  GI: ${currency.format(s.costoGI)}'),
          trailing: Text('G: ${currency.format(s.ganancia)}'),
        )),
      ]),
    );
  }

  Widget _kv(String k, String v, {bool bold=false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical:4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
      Text(k),
      Text(v, style: TextStyle(fontWeight: bold? FontWeight.bold : FontWeight.normal)),
    ]),
  );
}
