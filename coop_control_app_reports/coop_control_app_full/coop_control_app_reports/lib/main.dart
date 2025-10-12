
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
        child: Column(
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
              subtitle: 'Registro y resumen por día.',
              icon: Icons.bar_chart,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SalesScreen()),
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
  const _NavCard({required this.title, required this.subtitle, required this.icon, required this.onTap, super.key});
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

// ===== INVENTARIO =====
class InventoryItem {
  final String id;
  final String nombre;
  final String unidad;
  final double precioCompra;
  final double cantidad;

  InventoryItem({required this.id, required this.nombre, required this.unidad, required this.precioCompra, required this.cantidad});
  double get valorExistencia => precioCompra * cantidad;

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre, 'unidad': unidad, 'precioCompra': precioCompra, 'cantidad': cantidad};
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
}

class InventoryScreen extends StatefulWidget { const InventoryScreen({super.key}); @override State<InventoryScreen> createState() => _InventoryScreenState(); }
class _InventoryScreenState extends State<InventoryScreen> {
  final repo = InventoryRepo(); List<InventoryItem> items = [];
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { items = await repo.load(); setState((){}); }

  Future<void> _addOrEdit({InventoryItem? item}) async {
    final res = await showDialog<InventoryItem>(context: context, builder: (_) => _ItemDialog(item: item));
    if (res != null) {
      final i = items.indexWhere((e)=>e.id==res.id);
      if (i>=0) items[i]=res; else items.add(res);
      await repo.save(items); setState((){});
    }
  }

  Future<void> _ajustar(InventoryItem it) async {
    final c = TextEditingController(); String t='Entrada';
    final q = await showDialog<double>(context: context, builder: (_)=>AlertDialog(
      title: const Text('Movimiento de existencia'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: t, items: const [
          DropdownMenuItem(value:'Entrada', child: Text('Entrada')),
          DropdownMenuItem(value:'Salida', child: Text('Salida')),
        ], onChanged:(v)=>t=v??'Entrada'),
        const SizedBox(height:8),
        TextField(controller:c, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Cantidad'))
      ]),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: (){ final v=double.tryParse(c.text.replaceAll(',', '.'))??0; Navigator.pop(context, t=='Entrada'?v:-v); }, child: const Text('Aplicar'))
      ],
    ));
    if (q!=null && q!=0){
      final idx=items.indexWhere((e)=>e.id==it.id);
      items[idx]=InventoryItem(id: it.id, nombre: it.nombre, unidad: it.unidad, precioCompra: it.precioCompra, cantidad: (it.cantidad+q).clamp(0,double.infinity));
      await repo.save(items); setState((){});
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Artículo','Unidad','Precio compra','Existencia','Valor'];
    final data = items.map((e)=>[e.nombre,e.unidad,currency.format(e.precioCompra),e.cantidad.toStringAsFixed(2),currency.format(e.valorExistencia)]).toList();
    final total = items.fold<double>(0,(p,e)=>p+e.valorExistencia);
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Inventarios', style: pw.TextStyle(fontSize:20))),
      pw.Text('Fecha: '+dateFmt.format(DateTime.now())),
      pw.SizedBox(height:8),
      pw.Table.fromTextArray(headers: headers, data: data),
      pw.SizedBox(height:8),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Valor total: '+currency.format(total))),
    ]));
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'inventarios.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['Inventarios'];
    sheet.appendRow(['Artículo','Unidad','Precio compra','Existencia','Valor']);
    for (final e in items){ sheet.appendRow([e.nombre,e.unidad,e.precioCompra,e.cantidad,e.valorExistencia]); }
    final bytes = excel.encode()!;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/inventarios.xlsx';
    final file = File(path); await file.writeAsBytes(bytes, flush:true);
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context){
    final total = items.fold<double>(0,(p,e)=>p+e.valorExistencia);
    return Scaffold(
      appBar: AppBar(title: const Text('Inventarios'), actions: [
        PopupMenuButton<String>(onSelected:(v){ if(v=='pdf')_exportPdf(); if(v=='xlsx')_exportExcel(); }, itemBuilder:(_)=>const [
          PopupMenuItem(value:'pdf', child: Text('Exportar PDF')),
          PopupMenuItem(value:'xlsx', child: Text('Exportar Excel')),
        ])
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: ()=>_addOrEdit(), icon: const Icon(Icons.add), label: const Text('Artículo')),
      body: Column(children:[
        Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
          Text('Artículos: ${items.length}'),
          Text('Valor total: ${currency.format(total)}'),
        ])),
        Expanded(child: items.isEmpty? const Center(child: Text('Sin artículos registrados')):
          ListView.separated(itemCount: items.length, separatorBuilder: (_,__)=>
            const Divider(height:1), itemBuilder: (_ ,i){
              final it=items[i];
              return ListTile(
                title: Text(it.nombre),
                subtitle: Text('Unidad: ${it.unidad} · Precio: ${currency.format(it.precioCompra)}'),
                leading: CircleAvatar(child: Text(it.cantidad.toStringAsFixed(0))),
                trailing: Text('Existencia: ${it.cantidad.toStringAsFixed(2)}\n${currency.format(it.valorExistencia)}', textAlign: TextAlign.right),
                onTap: ()=>_addOrEdit(item: it),
                onLongPress: ()=>_ajustar(it),
              );
            })
        ),
      ]),
    );
  }
}

class _ItemDialog extends StatefulWidget { final InventoryItem? item; const _ItemDialog({this.item}); @override State<_ItemDialog> createState()=>_ItemDialogState(); }
class _ItemDialogState extends State<_ItemDialog> {
  late final TextEditingController nombre = TextEditingController(text: widget.item?.nombre ?? '');
  late final TextEditingController unidad = TextEditingController(text: widget.item?.unidad ?? 'unidad');
  late final TextEditingController precio = TextEditingController(text: widget.item?.precioCompra.toString() ?? '');
  late final TextEditingController cantidad = TextEditingController(text: widget.item?.cantidad.toString() ?? '0');
  @override Widget build(BuildContext context){
    return AlertDialog(title: Text(widget.item==null?'Nuevo artículo':'Editar artículo'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextField(controller:nombre, decoration: const InputDecoration(labelText:'Nombre')),
        const SizedBox(height:8),
        TextField(controller:unidad, decoration: const InputDecoration(labelText:'Unidad')),
        const SizedBox(height:8),
        TextField(controller:precio, decoration: const InputDecoration(labelText:'Precio de compra'), keyboardType: const TextInputType.numberWithOptions(decimal:true)),
        const SizedBox(height:8),
        TextField(controller:cantidad, decoration: const InputDecoration(labelText:'Existencia'), keyboardType: const TextInputType.numberWithOptions(decimal:true)),
      ])),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: (){
          final it = InventoryItem(
            id: widget.item?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
            nombre: nombre.text.trim(),
            unidad: unidad.text.trim(),
            precioCompra: double.tryParse(precio.text.replaceAll(',', '.')) ?? 0.0,
            cantidad: double.tryParse(cantidad.text.replaceAll(',', '.')) ?? 0.0,
          );
          Navigator.pop(context, it);
        }, child: const Text('Guardar')),
      ],
    );
  }
}

// ===== CAJA =====
class CashMove {
  final String id; final String fecha; final String tipo; final String concepto; final double monto;
  CashMove({required this.id, required this.fecha, required this.tipo, required this.concepto, required this.monto});
  Map<String, dynamic> toJson()=>{'id':id,'fecha':fecha,'tipo':tipo,'concepto':concepto,'monto':monto};
  factory CashMove.fromJson(Map<String, dynamic> j)=>CashMove(id:j['id'],fecha:j['fecha'],tipo:j['tipo'],concepto:j['concepto'],monto:(j['monto'] as num).toDouble());
}
class CashCount {
  final String id; final String fecha; final Map<String,int> denom;
  CashCount({required this.id, required this.fecha, required this.denom});
  double get total => 200*(denom['200']??0)+100*(denom['100']??0)+50*(denom['50']??0)+20*(denom['20']??0)+10*(denom['10']??0)+5*(denom['5']??0)+1*(denom['1']??0)+0.50*(denom['0.50']??0)+0.25*(denom['0.25']??0);
  Map<String, dynamic> toJson()=>{'id':id,'fecha':fecha,'denom':denom};
  factory CashCount.fromJson(Map<String, dynamic> j)=>CashCount(id:j['id'],fecha:j['fecha'],denom:(j['denom'] as Map).map((k,v)=>MapEntry(k.toString(), (v as num).toInt())));
}
class CashRepo {
  static const _mk='caja_movs_v1', _ck='caja_counts_v1';
  Future<List<CashMove>> loadMoves() async { final p=await SharedPreferences.getInstance(); final raw=p.getString(_mk); if(raw==null||raw.isEmpty)return[]; final list=(jsonDecode(raw) as List).cast<Map<String,dynamic>>(); return list.map(CashMove.fromJson).toList();}
  Future<void> saveMoves(List<CashMove> m) async { final p=await SharedPreferences.getInstance(); await p.setString(_mk, jsonEncode(m.map((e)=>e.toJson()).toList())); }
  Future<List<CashCount>> loadCounts() async { final p=await SharedPreferences.getInstance(); final raw=p.getString(_ck); if(raw==null||raw.isEmpty)return[]; final list=(jsonDecode(raw) as List).cast<Map<String,dynamic>>(); return list.map(CashCount.fromJson).toList();}
  Future<void> saveCounts(List<CashCount> c) async { final p=await SharedPreferences.getInstance(); await p.setString(_ck, jsonEncode(c.map((e)=>e.toJson()).toList())); }
}
class CashScreen extends StatefulWidget { const CashScreen({super.key}); @override State<CashScreen> createState()=>_CashScreenState(); }
class _CashScreenState extends State<CashScreen>{
  final repo = CashRepo(); List<CashMove> moves=[]; List<CashCount> counts=[];
  @override void initState(){ super.initState(); _load();}
  Future<void> _load() async { moves=await repo.loadMoves(); counts=await repo.loadCounts(); setState((){}); }
  double get saldoTeorico { final ing=moves.where((m)=>m.tipo=='Ingreso').fold<double>(0,(p,m)=>p+m.monto); final egr=moves.where((m)=>m.tipo=='Egreso').fold<double>(0,(p,m)=>p+m.monto); return ing-egr; }
  double? get ultimoArqueo { if (counts.isEmpty) return null; counts.sort((a,b)=>b.fecha.compareTo(a.fecha)); return counts.first.total; }
  Future<void> _addMove() async { final res=await showDialog<CashMove>(context: context, builder: (_)=>const _MoveDialog()); if(res!=null){ moves.add(res); await repo.saveMoves(moves); setState((){});} }
  Future<void> _addCount() async { final res=await showDialog<CashCount>(context: context, builder: (_)=>const _CountDialog()); if(res!=null){ counts.add(res); await repo.saveCounts(counts); setState((){});} }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers = ['Fecha','Tipo','Concepto','Monto'];
    final data = moves.map((m)=>[m.fecha,m.tipo,m.concepto,currency.format(m.monto)]).toList();
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Caja', style: pw.TextStyle(fontSize:20))),
      pw.Text('Fecha: '+dateFmt.format(DateTime.now())),
      pw.SizedBox(height:8),
      pw.Text('Saldo teórico: '+currency.format(saldoTeorico)),
      pw.SizedBox(height:8),
      pw.Table.fromTextArray(headers: headers, data: data),
      pw.SizedBox(height:8),
      pw.Text('Último arqueo: '+(ultimoArqueo==null?'sin registro':currency.format(ultimoArqueo!))),
      if(ultimoArqueo!=null) pw.Text('Diferencia: '+currency.format(ultimoArqueo!-saldoTeorico)),
    ]));
    final bytes = await pdf.save(); await Printing.sharePdf(bytes: bytes, filename: 'caja.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel();
    final s1=excel['Caja_Movimientos']; s1.appendRow(['Fecha','Tipo','Concepto','Monto']); for(final m in moves){ s1.appendRow([m.fecha,m.tipo,m.concepto,m.monto]); }
    final s2=excel['Caja_Arqueos']; s2.appendRow(['Fecha','Q200','Q100','Q50','Q20','Q10','Q5','Q1','Q0.50','Q0.25','Total']);
    for(final c in counts){ s2.appendRow([c.fecha,c.denom['200']??0,c.denom['100']??0,c.denom['50']??0,c.denom['20']??0,c.denom['10']??0,c.denom['5']??0,c.denom['1']??0,c.denom['0.50']??0,c.denom['0.25']??0,c.total]); }
    final bytes=excel.encode()!; final dir=await getTemporaryDirectory(); final path='${dir.path}/caja.xlsx'; final file=File(path); await file.writeAsBytes(bytes, flush:true); await Share.shareXFiles([XFile(path)]);
  }

  @override Widget build(BuildContext context){
    final dif = ultimoArqueo==null? null : (ultimoArqueo!-saldoTeorico);
    return Scaffold(
      appBar: AppBar(title: const Text('Caja'), actions:[
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
        Expanded(child: moves.isEmpty? const Center(child: Text('Sin movimientos')) :
          ListView.separated(itemCount: moves.length, separatorBuilder: (_,__)=>
            const Divider(height:1), itemBuilder: (_ ,i){
              final m=moves[i];
              return ListTile(
                leading: Icon(m.tipo=='Ingreso'? Icons.arrow_downward : Icons.arrow_upward),
                title: Text('${m.tipo} · ${currency.format(m.monto)}'),
                subtitle: Text('${m.concepto}\n${m.fecha}'),
                isThreeLine: true,
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { moves.removeAt(i); await repo.saveMoves(moves); setState((){}); }),
              );
            })
        ),
      ]),
    );
  }
}
class _MoveDialog extends StatefulWidget { const _MoveDialog(); @override State<_MoveDialog> createState()=>_MoveDialogState(); }
class _MoveDialogState extends State<_MoveDialog>{
  String tipo='Ingreso'; final concepto=TextEditingController(); final monto=TextEditingController();
  @override Widget build(BuildContext context){
    final hoy = dateFmt.format(DateTime.now());
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
      }, child: const Text('Guardar'))
    ]);
  }
}
class _CountDialog extends StatefulWidget { const _CountDialog(); @override State<_CountDialog> createState()=>_CountDialogState(); }
class _CountDialogState extends State<_CountDialog>{
  final Map<String, TextEditingController> ctrl = {'200':TextEditingController(text:'0'),'100':TextEditingController(text:'0'),'50':TextEditingController(text:'0'),'20':TextEditingController(text:'0'),'10':TextEditingController(text:'0'),'5':TextEditingController(text:'0'),'1':TextEditingController(text:'0'),'0.50':TextEditingController(text:'0'),'0.25':TextEditingController(text:'0')};
  double _calcTotal(){ double t=0; ctrl.forEach((k,v){ final c=int.tryParse(v.text)??0; final val=double.parse(k); t+=c*val; }); return t; }
  @override Widget build(BuildContext context){
    final hoy=dateFmt.format(DateTime.now());
    return StatefulBuilder(builder:(context,setStateSB){
      return AlertDialog(title: const Text('Arqueo de caja'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children:[
        Wrap(spacing:8, runSpacing:8, children: ctrl.keys.map((k)=>SizedBox(width:100, child: TextField(controller: ctrl[k], keyboardType: TextInputType.number, decoration: InputDecoration(labelText:'Q $k'), onChanged: (_)=>setStateSB((){})))).toList()),
        const SizedBox(height:8),
        Align(alignment: Alignment.centerLeft, child: Text('Total contado: ${currency.format(_calcTotal())}')),
      ])), actions:[
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: (){ final denom={for(final e in ctrl.entries) e.key: int.tryParse(e.value.text) ?? 0}; final cc=CashCount(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: hoy, denom: denom); Navigator.pop(context, cc); }, child: const Text('Guardar'))
      ]);
    });
  }
}

// ===== VENTAS =====
class Sale { final String id; final String fecha; final double monto; final String nota; Sale({required this.id, required this.fecha, required this.monto, required this.nota});
  Map<String, dynamic> toJson()=>{'id':id,'fecha':fecha,'monto':monto,'nota':nota};
  factory Sale.fromJson(Map<String, dynamic> j)=>Sale(id:j['id'],fecha:j['fecha'],monto:(j['monto'] as num).toDouble(),nota:j['nota']??'');
}
class SalesRepo { static const _key='ventas_diarias_v1';
  Future<List<Sale>> load() async { final p=await SharedPreferences.getInstance(); final raw=p.getString(_key); if(raw==null||raw.isEmpty)return[]; final list=(jsonDecode(raw) as List).cast<Map<String,dynamic>>(); return list.map(Sale.fromJson).toList(); }
  Future<void> save(List<Sale> sales) async { final p=await SharedPreferences.getInstance(); await p.setString(_key, jsonEncode(sales.map((e)=>e.toJson()).toList())); }
}
class SalesScreen extends StatefulWidget { const SalesScreen({super.key}); @override State<SalesScreen> createState()=>_SalesScreenState(); }
class _SalesScreenState extends State<SalesScreen>{
  final repo=SalesRepo(); List<Sale> sales=[];
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { sales=await repo.load(); setState((){}); }
  Future<void> _addSale() async { final res=await showDialog<Sale>(context: context, builder: (_)=>const _SaleDialog()); if(res!=null){ sales.add(res); await repo.save(sales); setState((){});} }
  Map<String,double> get diarios { final m=<String,double>{}; for(final s in sales){ m[s.fecha]=(m[s.fecha]??0)+s.monto; } return m; }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final headers=['Fecha','Monto','Notas'];
    final data=sales.map((s)=>[s.fecha,currency.format(s.monto),s.nota]).toList();
    final sum=sales.fold<double>(0,(p,s)=>p+s.monto);
    final byDay = diarios.entries.toList()..sort((a,b)=>b.key.compareTo(a.key));
    pdf.addPage(pw.MultiPage(build: (_)=>[
      pw.Header(level:0, child: pw.Text('Ventas diarias', style: pw.TextStyle(fontSize:20))),
      pw.Text('Fecha: '+dateFmt.format(DateTime.now())),
      pw.SizedBox(height:8),
      pw.Text('Acumulado: '+currency.format(sum)),
      pw.SizedBox(height:8),
      pw.Text('Resumen por día:'),
      pw.Table.fromTextArray(headers:['Día','Total'], data: byDay.map((e)=>[e.key, currency.format(e.value)]).toList()),
      pw.SizedBox(height:8),
      pw.Text('Detalle de ventas:'),
      pw.Table.fromTextArray(headers: headers, data: data),
    ]));
    final bytes=await pdf.save(); await Printing.sharePdf(bytes: bytes, filename: 'ventas.pdf');
  }

  Future<void> _exportExcel() async {
    final excel = ex.Excel.createExcel(); final s1=excel['Ventas']; s1.appendRow(['Fecha','Monto','Notas']); for(final s in sales){ s1.appendRow([s.fecha,s.monto,s.nota]); }
    final s2=excel['Resumen_por_dia']; s2.appendRow(['Día','Total']); diarios.forEach((k,v)=>s2.appendRow([k,v]));
    final bytes=excel.encode()!; final dir=await getTemporaryDirectory(); final path='${dir.path}/ventas.xlsx'; final file=File(path); await file.writeAsBytes(bytes, flush:true); await Share.shareXFiles([XFile(path)]);
  }

  @override Widget build(BuildContext context){
    final sum = sales.fold<double>(0,(p,s)=>p+s.monto);
    final grouped = diarios.entries.toList()..sort((a,b)=>b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Ventas diarias'), actions:[
        PopupMenuButton<String>(onSelected:(v){ if(v=='pdf')_exportPdf(); if(v=='xlsx')_exportExcel(); }, itemBuilder:(_)=>const [
          PopupMenuItem(value:'pdf', child: Text('Exportar PDF')),
          PopupMenuItem(value:'xlsx', child: Text('Exportar Excel')),
        ])
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed:_addSale, icon: const Icon(Icons.add), label: const Text('Venta')),
      body: Column(children:[
        Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
          Text('Registros: ${sales.length}'),
          Text('Acumulado: ${currency.format(sum)}'),
        ])),
        const Divider(),
        Expanded(child: grouped.isEmpty ? const Center(child: Text('Sin ventas registradas')) :
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
                    ...det.map((s)=>ListTile(title: Text(currency.format(s.monto)), subtitle: Text(s.nota))),
                  ]));
                },
              );
            })
        ),
      ]),
    );
  }
}
class _SaleDialog extends StatefulWidget { const _SaleDialog(); @override State<_SaleDialog> createState()=>_SaleDialogState(); }
class _SaleDialogState extends State<_SaleDialog>{
  final monto=TextEditingController(); final nota=TextEditingController();
  @override Widget build(BuildContext context){
    final hoy = dateFmt.format(DateTime.now());
    return AlertDialog(title: const Text('Nueva venta'), content: Column(mainAxisSize: MainAxisSize.min, children:[
      TextField(controller:monto, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Monto')),
      const SizedBox(height:8),
      TextField(controller: nota, decoration: const InputDecoration(labelText:'Nota (opcional)')),
    ]), actions:[
      TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: (){
        final s = Sale(id: DateTime.now().millisecondsSinceEpoch.toString(), fecha: hoy, monto: double.tryParse(monto.text.replaceAll(',', '.')) ?? 0.0, nota: nota.text.trim());
        Navigator.pop(context, s);
      }, child: const Text('Guardar')),
    ]);
  }
}
