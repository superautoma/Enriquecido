import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/main_quill_integrated_test.dart';

ToolItem tool(int id, {String name='Taladro', double quantity=1, int? parentId, bool isSet=false}) =>
  ToolItem(id:id,name:name,description:'Descripción',descriptionDelta:'',barcode:'',
    quantity:quantity,unit:'ud',minimumStock:0,purchasePrice:0,condition:'Bueno',
    type:'Herramienta manual',parentId:parentId,isSet:isSet);
LoanDraft lend({double? quantity, Map<int,double>? contents, String name='Pedro'}) =>
  LoanDraft(borrower:name,startedOn:loanDay(DateTime.now()).subtract(const Duration(days:3)),
    quantity:quantity,contents:contents,contact:'600000000',accessories:'Maletín',
    deliveryCondition:'Completa',notes:'Con batería');

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll((){sqfliteFfiInit();databaseFactory=databaseFactoryFfi;});
  setUp(()async{
    dir=await Directory.systemTemp.createTemp('management_');
    await databaseFactory.setDatabasesPath('${dir.path}/database');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),(_)async=>dir.path);
  });
  tearDown(()async{
    await ToolsDatabase.instance.closeForBackup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),null);
    await dir.delete(recursive:true);
  });

  test('v8 migration preserves an active loan, photographs, state and tool ID',()async{
    final path='${dir.path}/database/gestor_herramientas.db';
    final db=await openDatabase(path,version:8,onCreate:(db,v)async{
      await db.execute('''CREATE TABLE tools(id INTEGER PRIMARY KEY,name TEXT NOT NULL,
        description TEXT,description_delta TEXT,barcode TEXT,quantity REAL,unit TEXT,
        minimum_stock REAL,purchase_price REAL,condition TEXT,tool_type TEXT,voltage TEXT,image_path TEXT)''');
      await db.execute('''CREATE TABLE tool_images(id INTEGER PRIMARY KEY,tool_id INTEGER,path TEXT,
        description TEXT,type TEXT,position INTEGER,is_primary INTEGER,created_at TEXT)''');
      await db.execute('''CREATE TABLE tool_loans(id INTEGER PRIMARY KEY AUTOINCREMENT,tool_id INTEGER,
        tool_name TEXT,borrower TEXT,started_on TEXT,due_on TEXT,returned_on TEXT,notes TEXT,
        previous_condition TEXT,quantity REAL,unit TEXT)''');
      await db.execute('CREATE UNIQUE INDEX idx_tool_active_loan ON tool_loans(tool_id) WHERE returned_on IS NULL');
      await db.insert('tools',{'id':42,'name':'Juego','description':'Siete piezas','quantity':1,
        'unit':'ud','condition':'Prestado','tool_type':'Herramienta manual','voltage':'24 V','image_path':'/foto.jpg'});
      await db.insert('tool_loans',{'tool_id':42,'tool_name':'Juego','borrower':'Ana',
        'started_on':'2026-01-01T00:00:00.000','notes':'Antiguo','previous_condition':'Bueno','quantity':1,'unit':'ud'});
    });
    await db.close();
    final loaded=(await ToolsDatabase.instance.loadTools()).single;
    expect(loaded.id,42);expect(loaded.description,'Siete piezas');expect(loaded.voltage,'24 V');
    expect(loaded.activeLoan!.borrower,'Ana');expect(loaded.activeLoan!.pendingQuantity,1);
    expect(loaded.images.single.path,'/foto.jpg');
    expect(await (await ToolsDatabase.instance.database).getVersion(),toolsDatabaseVersion);
    await ToolsDatabase.instance.returnLoan(loaded.activeLoan!.id,DateTime.now());
    expect((await ToolsDatabase.instance.loadTool(42))!.condition,'Bueno');
  });

  test('Partial quantities allow multiple borrowers without lending the same stock twice',()async{
    final db=ToolsDatabase.instance;
    await db.saveTool(tool(1,quantity:3)..loanDraft=lend(quantity:2));
    final first=(await db.loadLoans()).single;
    expect((await db.loadTool(1))!.availableQuantity,1);
    await db.saveTool((await db.loadTool(1))!..loanDraft=lend(quantity:1,name:'Ana'));
    await expectLater(db.saveTool((await db.loadTool(1))!..loanDraft=lend(quantity:1)),throwsStateError);
    await db.recordReturn(first.id,LoanReturnDraft(date:DateTime.now(),quantity:1,notes:'Una unidad devuelta'));
    expect((await db.loadLoans()).where((l)=>l.id==first.id).single.isActive,true);
    expect((await db.loadTool(1))!.availableQuantity,1);
    await expectLater(db.saveTool((await db.loadTool(1))!..quantity=1),throwsStateError);
    await expectLater(db.recordReturn(first.id,LoanReturnDraft(date:DateTime.now(),quantity:2)),throwsStateError);
    expect((await db.loadLoans()).where((l)=>l.id==first.id).single.pendingQuantity,1);
    await db.recordReturn(first.id,LoanReturnDraft(date:DateTime.now(),quantity:1));
    expect((await db.loadTool(1))!.condition,'Prestado'); // Ana still has a unit.
    final second=(await db.loadLoans()).where((l)=>l.isActive).single;
    await db.returnLoan(second.id,DateTime.now());
    expect((await db.loadTool(1))!.condition,'Bueno');
    expect(await db.loadBorrowers(),hasLength(2));
  });

  test('Set pieces, full loan, partial return and maintenance cannot duplicate availability',()async{
    final db=ToolsDatabase.instance;
    await db.saveTool(tool(1,name:'Juego de destornilladores',isSet:true));
    await db.saveTool(tool(2,name:'Plano',quantity:4,parentId:1));
    await db.saveTool(tool(3,name:'Estrella',quantity:3,parentId:1));
    expect(await db.loadTools(),hasLength(1));
    expect(await db.loadTools(includeComponents:true),hasLength(3));
    await db.saveTool((await db.loadTool(1))!..loanDraft=lend());
    final loan=(await db.loadLoans()).single;
    final contents=await db.loadLoanContents(loan.id);
    expect(contents,hasLength(2));
    await expectLater(db.saveTool((await db.loadTool(2))!..loanDraft=lend(quantity:1)),throwsStateError);
    await expectLater(db.detachComponent(2),throwsStateError);
    await db.recordReturn(loan.id,LoanReturnDraft(date:DateTime.now(),contents:{
      for(final c in contents)c.id:c.componentId==2?4:2},notes:'Falta un destornillador'));
    expect((await db.loadTool(2))!.availableQuantity,4);
    expect((await db.loadTool(3))!.availableQuantity,2);
    expect((await db.loadLoans()).single.isActive,true);
    final pending=(await db.loadLoanContents(loan.id)).firstWhere((c)=>c.pending>0);
    await db.recordReturn(loan.id,LoanReturnDraft(date:DateTime.now(),contents:{pending.id:1},needsMaintenance:true));
    expect((await db.loadLoans()).single.isActive,false);
    expect((await db.loadTool(3))!.outOfService,true);
    await expectLater(db.saveTool((await db.loadTool(1))!..loanDraft=lend()),throwsStateError);
    await db.setOutOfService(3,false,'Revisado');
    await db.saveTool((await db.loadTool(1))!..loanDraft=lend(contents:{2:1}));
    final partial=(await db.loadLoans()).first;
    expect(partial.quantity,0);expect((await db.loadTool(2))!.availableQuantity,3);
    await expectLater(db.saveTool((await db.loadTool(1))!..loanDraft=lend()),throwsStateError);
  });

  test('Historical returns keep the final date and stale editors preserve maintenance blocks',()async{
    final db=ToolsDatabase.instance;
    await db.saveTool(tool(1,quantity:2)..loanDraft=lend());
    final loan=(await db.loadLoans()).single;
    final stale=(await db.loadTool(1))!;
    final latest=loanDay(DateTime.now());
    await db.recordReturn(loan.id,LoanReturnDraft(date:latest,quantity:1,needsMaintenance:true));
    await db.recordReturn(loan.id,LoanReturnDraft(date:latest.subtract(const Duration(days:1)),quantity:1));
    expect((await db.loadLoans()).single.returnedOn,latest);
    await db.saveTool(stale);
    expect((await db.loadTool(1))!.outOfService,true);
    await expectLater(db.saveTool((await db.loadTool(1))!..loanDraft=lend(quantity:1)),throwsStateError);
  });

  test('Loans and changes retain audit entries and reject dates after partial returns',()async{
    final db=ToolsDatabase.instance;
    await db.saveTool(tool(1,quantity:2)..loanDraft=lend());
    final loan=(await db.loadLoans()).single;
    final day=loanDay(DateTime.now()).subtract(const Duration(days:1));
    await db.recordReturn(loan.id,LoanReturnDraft(date:day,quantity:1,notes:'Entrega parcial'));
    await expectLater(db.updateLoan(loan.id,LoanDraft(borrower:'Ana',startedOn:DateTime.now())),throwsStateError);
    await db.updateLoan(loan.id,LoanDraft(borrower:'Ana',startedOn:loan.startedOn,
      dueOn:DateTime.now().add(const Duration(days:7)),notes:'Plazo ampliado',contact:'611111111'));
    expect((await db.loanEvents(loan.id)).map((e)=>e['kind']),containsAll(['Entrega','Devolución','Modificación']));
    expect((await db.loadLoans()).single.pendingQuantity,1);
    expect((await db.loadLoans()).single.contact,'611111111');
  });

  test('Maintenance calendar clamps end of month and reopens after backup with attachments',()async{
    final db=ToolsDatabase.instance;
    await db.saveTool(tool(1));
    final task=MaintenanceTask(toolId:1,title:'Revisión',dueOn:DateTime(2026,1,31),interval:1);
    expect(task.nextAfter(DateTime(2026,1,31)),DateTime(2026,2,28));
    final id=await db.saveMaintenance(task);
    await db.saveMaintenanceRecord(MaintenanceRecord(taskId:id,date:DateTime(2026,1,31),notes:'Revisado',parts:'Escobillas',cost:12));
    expect((await db.loadMaintenance()).single.dueOn,DateTime(2026,2,28));
    final record=(await db.maintenanceRecords(id)).single;
    await db.saveMaintenanceRecord(MaintenanceRecord(id:record.id,taskId:id,date:DateTime(2026,2,28),notes:'Fecha corregida'));
    expect((await db.loadMaintenance()).single.dueOn,DateTime(2026,3,28));
    final directory=await toolDocumentsDirectory();
    final file=File('${directory.path}/manual.pdf');await file.writeAsString('%PDF prueba adjunto');
    final doc=ToolDocument(toolId:1,name:'Manual en español',fileName:'manual.pdf');
    final docId=await db.saveDocument(doc);
    final backup=await BackupManager.createBackup();
    await db.deleteDocument(ToolDocument(id:docId,toolId:1,name:doc.name,fileName:doc.fileName));
    expect(await file.exists(),false);
    await BackupManager.restoreBackup(backup.path);
    expect((await db.loadDocuments(1)).single.name,doc.name);
    expect(await file.readAsString(),'%PDF prueba adjunto');
    expect((await db.loadMaintenance()).single.dueOn,DateTime(2026,3,28));
    expect((await db.maintenanceRecords(id)).single.notes,'Fecha corregida');
    await expectLater(db.saveDocument(const ToolDocument(toolId:1,name:'Enlace',url:'file:///etc/passwd')),throwsStateError);
  });

  testWidgets('Management shortcuts stay usable on a narrow screen with large text',(tester)async{
    tester.view.physicalSize=const Size(320,700);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(textScaler:TextScaler.linear(2)),
      child:Scaffold(body:ManagementShortcuts(onOpen:(v)=>selected=v)))));
    for(final section in managementSections){expect(find.byIcon(section.$3),findsOneWidget);}
    await tester.tap(find.byKey(const ValueKey('management_documents')));expect(selected,'documents');
    expect(tester.takeException(),isNull);
  });
}
