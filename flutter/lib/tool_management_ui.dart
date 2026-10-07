part of 'main_quill_integrated_test.dart';

void managementError(BuildContext context, Object error) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))));
}

const managementSections = <(String, String, IconData)>[
  ('contents', 'Conjunto', Icons.widgets_outlined),
  ('documents', 'Documentos', Icons.description_outlined),
  ('maintenance', 'Mantenimiento', Icons.build_outlined),
  ('loans', 'Préstamos', Icons.handshake_outlined),
];

class ManagementShortcuts extends StatelessWidget {
  const ManagementShortcuts({super.key, required this.onOpen});
  final void Function(String)? onOpen;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 4, runSpacing: 4,
    alignment: WrapAlignment.spaceAround, children: [
      for (final section in managementSections) Tooltip(message: section.$2,
        child: InkWell(key: ValueKey('management_${section.$1}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen == null ? null : () => onOpen!(section.$1),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(section.$3, size: 26, color: managementColor),
              const SizedBox(height: 4), Text(section.$2,
                style: const TextStyle(fontSize: 11, color: managementColor)),
            ])))),
    ]);
}

Future<void> openToolManagement(BuildContext context, ToolItem tool, String section) async {
  Widget page;
  switch (section) {
    case 'contents': page = ComponentsPage(tool: tool);
    case 'documents': page = DocumentsPage(toolId: tool.id, toolName: tool.name);
    case 'maintenance': page = MaintenancePage(toolId: tool.id, toolName: tool.name);
    default: page = LoansPage(toolId: tool.id, toolName: tool.name);
  }
  await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
}

Future<ToolItem?> chooseManagedTool(BuildContext context, {bool rootsOnly = false}) async {
  final tools = await ToolsDatabase.instance.loadTools(includeComponents: !rootsOnly);
  if (!context.mounted) return null;
  return showDialog<ToolItem>(context: context, builder: (_) => _ToolChooser(tools: tools));
}
class _ToolChooser extends StatefulWidget {
  const _ToolChooser({required this.tools});
  final List<ToolItem> tools;
  @override
  State<_ToolChooser> createState() => _ToolChooserState();
}
class _ToolChooserState extends State<_ToolChooser> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final tools = widget.tools.where((t) => t.name.toLowerCase().contains(_query)).toList();
    return AlertDialog(title: const Text('Seleccionar herramienta'),
      content: SizedBox(width: 440, height: 420, child: Column(children: [
        TextField(onChanged: (v) => setState(() => _query = v.toLowerCase()),
          decoration: const InputDecoration(labelText: 'Buscar', prefixIcon: Icon(Icons.search))),
        const SizedBox(height: 10), Expanded(child: ListView.builder(
          itemCount: tools.length, itemBuilder: (_, i) => ListTile(
            leading: Icon(tools[i].isSet ? Icons.widgets_outlined : Icons.handyman_outlined),
            title: Text(tools[i].name), subtitle: Text(tools[i].parentId == null ? tools[i].type : 'Pieza de un conjunto'),
            onTap: () => Navigator.pop(context, tools[i])))),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))]);
  }
}

class ManagementHubPage extends StatefulWidget {
  const ManagementHubPage({super.key});
  @override
  State<ManagementHubPage> createState() => _ManagementHubPageState();
}
class _ManagementHubPageState extends State<ManagementHubPage> {
  List<ToolItem> _tools = [];
  List<ToolLoan> _loans = [];
  List<MaintenanceTask> _tasks = [];
  int _documents = 0;
  bool _loading = true;
  bool _notifications = false;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final db = ToolsDatabase.instance;
      final tools = await db.loadTools(includeComponents: true);
      final loans = await db.loadLoans();
      final tasks = await db.loadMaintenance();
      final sql = await db.database;
      final documents = Sqflite.firstIntValue(await sql.rawQuery('SELECT COUNT(*) FROM tool_documents')) ?? 0;
      final settings = await sql.query('management_settings', where: 'key=?', whereArgs: ['notifications']);
      if (mounted) setState(() { _tools=tools; _loans=loans; _tasks=tasks; _documents=documents;
        _notifications = settings.isNotEmpty && settings.single['value']=='1'; _loading=false; _error=null; });
    } catch (error) { if (mounted) setState(() { _error='$error'; _loading=false; }); }
  }
  Future<void> _open(String section) async {
    try {
      if (section == 'loans' || section == 'maintenance') {
        if (!mounted) return;
        await Navigator.push<void>(context, MaterialPageRoute(builder: (_) =>
          section == 'loans' ? const LoansPage() : const MaintenancePage()));
      } else {
        final tool = await chooseManagedTool(context, rootsOnly: section == 'contents');
        if (tool == null || !mounted) return;
        await openToolManagement(context, tool, section);
      }
      if (mounted) await _load();
    } catch (error) { if (mounted) managementError(context, error); }
  }
  Future<void> _toggleNotifications(bool value) async {
    try {
      await (await ToolsDatabase.instance.database).insert('management_settings',
        {'key':'notifications','value':value?'1':'0'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await syncManagementReminders(requestPermission: value);
      if (mounted) setState(() => _notifications=value);
    } catch (error) { if (mounted) managementError(context, error); }
  }
  @override
  Widget build(BuildContext context) {
    final pendingLoans = _loans.where((l)=>l.isActive).toList();
    final dueTasks = _tasks.where((t)=>t.enabled &&
      !loanDay(t.dueOn).isAfter(loanDay(DateTime.now()).add(const Duration(days:7)))).toList();
    final labels = <String,String>{
      'contents':'${_tools.where((t)=>t.isSet).length} conjuntos · ${_tools.where((t)=>t.parentId!=null).length} fichas de piezas',
      'documents':'$_documents documentos adjuntos o enlaces',
      'maintenance':'${dueTasks.length} tareas pendientes o próximas',
      'loans':'${pendingLoans.length} activos · ${pendingLoans.where((l)=>l.isOverdue).length} atrasados',
    };
    return Scaffold(appBar: AppBar(title: const Text('Gestión de herramientas')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _error!=null ?
        Center(child: TextButton(onPressed:_load, child: const Text('Reintentar carga'))) :
      RefreshIndicator(onRefresh:_load, child: ListView(padding: const EdgeInsets.all(16), children: [
        for(final section in managementSections) Card(child: ListTile(
          leading: Icon(section.$3, color: managementColor, size:30), title: Text(section.$2),
          subtitle: Text(labels[section.$1]!), trailing: const Icon(Icons.chevron_right),
          onTap:()=>_open(section.$1))),
        const SizedBox(height:12),
        SwitchListTile.adaptive(title: const Text('Avisos en el teléfono'),
          secondary: const Icon(Icons.notifications_none_outlined),
          subtitle: const Text('Préstamos y mantenimientos. La antelación se configura en cada registro.'),
          value:_notifications, onChanged:_toggleNotifications),
        if (pendingLoans.any((l)=>l.isOverdue) || dueTasks.isNotEmpty) ...[
          const SizedBox(height:16), const SectionTitle('Pendiente'),
          for(final loan in pendingLoans.where((l)=>l.isOverdue)) ListTile(
            leading: const Icon(Icons.handshake_outlined, color:Colors.deepOrange),
            title:Text(loan.toolName), subtitle:Text('Devolución: ${loan.borrower} · ${loanDateText(loan.dueOn!)}'),
            onTap:() async { await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>LoanDetailsPage(loan:loan))); await _load(); }),
          for(final task in dueTasks) ListTile(
            leading:Icon(Icons.build_outlined, color:task.isOverdue?Colors.deepOrange:managementColor),
            title:Text('${task.toolName} · ${task.title}'), subtitle:Text(loanDateText(task.dueOn)),
            onTap:() async { await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>MaintenanceDetailsPage(task:task))); await _load(); }),
        ],
      ])));
  }
}

class ComponentsPage extends StatefulWidget {
  const ComponentsPage({super.key, required this.tool});
  final ToolItem tool;
  @override
  State<ComponentsPage> createState()=>_ComponentsPageState();
}
class _ComponentsPageState extends State<ComponentsPage> {
  List<ToolItem> _components=[];
  late ToolItem _tool;
  bool _busy=false;
  bool _loading=true;
  @override
  void initState(){ super.initState(); _tool=widget.tool; _load(); }
  Future<void> _load() async {
    try {
      final tool = await ToolsDatabase.instance.loadTool(_tool.id);
      final components=await ToolsDatabase.instance.loadComponents(_tool.id);
      if(mounted) setState((){ if(tool!=null)_tool=tool; _components=components; _loading=false; });
    } catch(error){ if(mounted) managementError(context,error); }
  }
  Future<void> _enable() async {
    try {
      _tool.isSet=true;
      await ToolsDatabase.instance.saveTool(_tool);
      await _load();
    } catch(error){ if(mounted) managementError(context,error); }
  }
  Future<void> _edit([ToolItem? component]) async {
    if(_busy)return;
    setState(()=>_busy=true);
    try {
      final id=await ToolsDatabase.instance.nextToolId();
      final item=component?.copy() ?? ToolItem(id:id,name:'',description:'',descriptionDelta:'',
        barcode:'',quantity:1,unit:'ud',minimumStock:0,purchasePrice:0,condition:'Bueno',
        type:_tool.type, parentId:_tool.id);
      if(!mounted)return;
      final result=await Navigator.push<ToolItem>(context,MaterialPageRoute(builder:(_)=>
        EditToolPage(item:item,nextId:id)));
      if(result!=null) await ToolsDatabase.instance.saveTool(result);
      await _load();
    } catch(error){ if(mounted)managementError(context,error); }
    finally{ if(mounted)setState(()=>_busy=false); }
  }
  Future<void> _link() async {
    try {
      final tool=await chooseManagedTool(context,rootsOnly:true);
      if(tool==null || !mounted)return;
      if(tool.isSet || tool.id==_tool.id) throw StateError('Selecciona una herramienta individual');
      tool.parentId=_tool.id;
      await ToolsDatabase.instance.saveTool(tool);
      await _load();
    } catch(error){ if(mounted)managementError(context,error); }
  }
  Future<void> _detach(ToolItem tool) async {
    final confirm=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
      title:const Text('Desvincular pieza'),content:Text('${tool.name} pasará a ser una herramienta independiente y conservará su historial.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Desvincular'))]));
    if(confirm!=true || !mounted)return;
    try{ await ToolsDatabase.instance.detachComponent(tool.id); await _load(); }
    catch(error){ if(mounted)managementError(context,error); }
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text('Contenido · ${_tool.name}')),
    floatingActionButton:_tool.isSet?FloatingActionButton(tooltip:'Añadir pieza',onPressed:_busy?null:()=>_edit(),child:const Icon(Icons.add)):null,
    body:_loading?const Center(child:CircularProgressIndicator()):ListView(
      padding:const EdgeInsets.fromLTRB(16,16,16,100),children:[
      if(!_tool.isSet) ...[
        const Text('Activa la opción de conjunto para vincular sus piezas.'),
        const SizedBox(height:16),FilledButton.icon(onPressed:_enable,
          icon:const Icon(Icons.widgets_outlined),label:const Text('Es un conjunto')),
      ] else ...[
        Text('${_components.length} fichas · ${formatNumber(_components.fold<double>(0,(n,t)=>n+t.quantity))} piezas',
          style:const TextStyle(fontWeight:FontWeight.w700)),
        const SizedBox(height:8),
        const Text('Las piezas pertenecen a este conjunto y se consultan desde aquí.'),
        const SizedBox(height:8),OutlinedButton.icon(onPressed:_link,
          icon:const Icon(Icons.link_outlined),label:const Text('Vincular herramienta existente')),
        if(_components.isEmpty) const Padding(padding:EdgeInsets.all(20),child:Text('Añade la primera pieza con +.')),
        for(final tool in _components) Card(child:ListTile(
          leading:const Icon(Icons.extension_outlined,color:managementColor),title:Text(tool.name),
          subtitle:Text('${formatNumber(tool.quantity)} ${tool.unit} · '
            '${tool.outOfService ? 'Fuera de servicio' : '${formatNumber(tool.availableQuantity??tool.quantity)} disponibles'}'),
          onTap:()=>_edit(tool),trailing:PopupMenuButton<String>(onSelected:(v){
            if(v=='detach')_detach(tool); else openToolManagement(context,tool,v).then((_){if(mounted)_load();});
          },itemBuilder:(_)=>const[
            PopupMenuItem(value:'documents',child:Text('Documentos')),
            PopupMenuItem(value:'maintenance',child:Text('Mantenimiento')),
            PopupMenuItem(value:'loans',child:Text('Préstamos')),
            PopupMenuItem(value:'detach',child:Text('Desvincular')),
          ]))),
      ],
    ]));
}

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key,required this.toolId,required this.toolName,this.loanId,this.taskId,this.defaultKind='Manual'});
  final int toolId;
  final String toolName;
  final int? loanId;
  final int? taskId;
  final String defaultKind;
  @override
  State<DocumentsPage> createState()=>_DocumentsPageState();
}
class _DocumentsPageState extends State<DocumentsPage>{
  List<ToolDocument> _documents=[];
  bool _loading=true;
  String? _error;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load() async {
    try{final docs=await ToolsDatabase.instance.loadDocuments(widget.toolId,loanId:widget.loanId,taskId:widget.taskId);
      if(mounted)setState((){_documents=docs;_loading=false;_error=null;});
    }catch(error){if(mounted)setState((){_loading=false;_error='$error';});}
  }
  Future<void> _edit([ToolDocument? doc]) async {
    await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>DocumentEditorPage(
      toolId:widget.toolId,loanId:widget.loanId,taskId:widget.taskId,
      initial:doc,defaultKind:widget.defaultKind)));
    if(mounted)await _load();
  }
  Future<void> _open(ToolDocument doc) async {
    try{
      if(doc.isLink){await managementChannel.invokeMethod<void>('openUrl',{'url':doc.url});return;}
      final path=p.join((await toolDocumentsDirectory()).path,doc.fileName);
      if(!await File(path).exists())throw StateError('No se encuentra el archivo adjunto');
      if(const ['.jpg','.jpeg','.png','.webp','.gif'].contains(p.extension(path).toLowerCase())){
        if(!mounted)return;
        await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>Scaffold(
          appBar:AppBar(title:Text(doc.name)),body:Center(child:InteractiveViewer(child:Image.file(File(path)))))));
      }else{await managementChannel.invokeMethod<void>('openFile',{'path':path});}
    }catch(error){if(mounted)managementError(context,error);}
  }
  Future<void> _action(ToolDocument doc,String action) async {
    try{
      if(action=='edit'){await _edit(doc);return;}
      if(action=='share'){
        if(doc.isLink){await Share.share(doc.url);}else{
          final path=p.join((await toolDocumentsDirectory()).path,doc.fileName);
          await Share.shareXFiles([XFile(path)],text:doc.name);
        }return;
      }
      final confirm=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
        title:const Text('Eliminar documento'),content:Text('¿Eliminar ${doc.name}?'),
        actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancelar')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Eliminar'))]));
      if(confirm!=true)return;
      await ToolsDatabase.instance.deleteDocument(doc);await _load();
    }catch(error){if(mounted)managementError(context,error);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Documentos · ${widget.toolName}')),
    floatingActionButton:FloatingActionButton(tooltip:'Añadir documento',onPressed:()=>_edit(),child:const Icon(Icons.note_add_outlined)),
    body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?
      Center(child:TextButton(onPressed:_load,child:const Text('Reintentar carga'))):_documents.isEmpty?
      const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Añade manuales, fotografías, documentos o enlaces con +.'))):
      ListView(padding:const EdgeInsets.fromLTRB(12,12,12,100),children:[for(final doc in _documents)
        Card(child:ListTile(leading:Icon(doc.isLink?Icons.link_outlined:Icons.description_outlined,color:managementColor),
          title:Text(doc.name),subtitle:Text(doc.kind),onTap:()=>_open(doc),
          trailing:PopupMenuButton<String>(onSelected:(v)=>_action(doc,v),itemBuilder:(_)=>const[
            PopupMenuItem(value:'edit',child:Text('Editar / sustituir')),
            PopupMenuItem(value:'share',child:Text('Compartir')),
            PopupMenuItem(value:'delete',child:Text('Eliminar')),
          ])))]));
}

class DocumentEditorPage extends StatefulWidget{
  const DocumentEditorPage({super.key,required this.toolId,this.initial,this.loanId,this.taskId,this.defaultKind='Manual'});
  final int toolId;final ToolDocument? initial;final int? loanId;final int? taskId;final String defaultKind;
  @override
  State<DocumentEditorPage> createState()=>_DocumentEditorPageState();
}
class _DocumentEditorPageState extends State<DocumentEditorPage>{
  final _form=GlobalKey<FormState>();
  final _name=TextEditingController();final _url=TextEditingController();
  String _kind='Manual';String _fileName='';String? _copied;bool _link=false;bool _busy=false;bool _saved=false;
  @override
  void initState(){super.initState();final doc=widget.initial;
    _name.text=doc?.name??'';_url.text=doc?.url??'';_fileName=doc?.fileName??'';
    _kind=doc?.kind??widget.defaultKind;_link=doc?.isLink??false;}
  @override
  void dispose(){_name.dispose();_url.dispose();
    if(!_saved && _copied!=null)File(_copied!).delete().catchError((Object e)=>File(_copied!));
    super.dispose();}
  Future<void> _copy(String path,String name)async{
    final dir=await toolDocumentsDirectory();
    final safeName=name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
    final filename='${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final target=await File(path).copy(p.join(dir.path,filename));
    if(_copied!=null && await File(_copied!).exists())await File(_copied!).delete();
    _copied=target.path;
    if(mounted)setState((){_fileName=filename;_link=false;if(_name.text.trim().isEmpty)_name.text=name;});
  }
  Future<void> _pick()async{
    try{final picked=await FilePicker.platform.pickFiles();
      if(picked==null || picked.files.single.path==null)return;
      await _copy(picked.files.single.path!,picked.files.single.name);
    }catch(error){if(mounted)managementError(context,error);}
  }
  Future<void> _photo(ImageSource source)async{
    try{final image=await ImagePicker().pickImage(source:source,imageQuality:90);
      if(image!=null)await _copy(image.path,image.name);
    }catch(error){if(mounted)managementError(context,error);}
  }
  Future<void> _save()async{
    if(_busy || !(_form.currentState?.validate()??false))return;
    setState(()=>_busy=true);
    try{
      await ToolsDatabase.instance.saveDocument(ToolDocument(id:widget.initial?.id,toolId:widget.toolId,
        name:_name.text,kind:_kind,fileName:_link?'':_fileName,url:_link?_url.text.trim():'',
        loanId:widget.initial?.loanId??widget.loanId,taskId:widget.initial?.taskId??widget.taskId));
      _saved=true;if(mounted)Navigator.pop(context,true);
    }catch(error){if(mounted){managementError(context,error);setState(()=>_busy=false);}}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.initial==null?'Añadir documento':'Editar documento')),
    body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(16),children:[
      TextFormField(key:const ValueKey('document_name'),controller:_name,decoration:const InputDecoration(labelText:'Nombre*',prefixIcon:Icon(Icons.description_outlined)),
        validator:(v)=>v==null||v.trim().isEmpty?'Pon un nombre':null),
      const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:_kind,isExpanded:true,
        decoration:const InputDecoration(labelText:'Tipo de documento'),items:[for(final k in const[
          'Manual','Instrucciones','Despiece','Garantía','Factura','Entrega','Devolución','Mantenimiento','Otro'])
          DropdownMenuItem(value:k,child:Text(k))],onChanged:(v){if(v!=null)setState(()=>_kind=v);}),
      SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,title:const Text('Guardar un enlace'),
        secondary:const Icon(Icons.link_outlined),value:_link,onChanged:(v)=>setState(()=>_link=v)),
      if(_link)TextFormField(key:const ValueKey('document_url'),controller:_url,keyboardType:TextInputType.url,
        decoration:const InputDecoration(labelText:'Enlace https://…'),validator:(v){
          final uri=Uri.tryParse(v?.trim()??'');return uri!=null&&['http','https'].contains(uri.scheme)&&uri.host.isNotEmpty?null:'Escribe un enlace completo';})
      else ...[
        Text(_fileName.isEmpty?'Sin archivo adjunto':_fileName.split('_').skip(1).join('_')),
        const SizedBox(height:8),OutlinedButton.icon(onPressed:_pick,icon:const Icon(Icons.attach_file),label:const Text('Elegir / sustituir archivo')),
        Wrap(spacing:8,children:[TextButton.icon(onPressed:()=>_photo(ImageSource.camera),icon:const Icon(Icons.camera_alt_outlined),label:const Text('Cámara')),
          TextButton.icon(onPressed:()=>_photo(ImageSource.gallery),icon:const Icon(Icons.photo_outlined),label:const Text('Fotografía'))]),
        const Text('El archivo se conservará en la aplicación y en sus copias de seguridad.'),
      ],
      const SizedBox(height:24),FilledButton.icon(onPressed:_busy?null:_save,
        icon:const Icon(Icons.check),label:Text(_busy?'Guardando…':'Guardar documento')),
    ])));
}

class ReminderSelector extends StatelessWidget{
  const ReminderSelector({super.key,required this.value,required this.onChanged});
  final int value;final void Function(int) onChanged;
  @override
  Widget build(BuildContext context)=>DropdownButtonFormField<int>(initialValue:value,
    isExpanded:true,decoration:const InputDecoration(labelText:'Aviso',prefixIcon:Icon(Icons.notifications_none_outlined)),
    items:[for(final days in [-1,0,1,3,7,if(![-1,0,1,3,7].contains(value))value])
      DropdownMenuItem(value:days,child:Text(days<0?'Sin aviso':days==0?'El mismo día':days==1?'Un día antes':'$days días antes'))],
    onChanged:(v){if(v!=null)onChanged(v);});
}

class MaintenancePage extends StatefulWidget{
  const MaintenancePage({super.key,this.toolId,this.toolName});
  final int? toolId;final String? toolName;
  @override
  State<MaintenancePage> createState()=>_MaintenancePageState();
}
class _MaintenancePageState extends State<MaintenancePage>{
  List<MaintenanceTask> _tasks=[];ToolItem? _tool;bool _loading=true;String? _error;int _view=0;
  @override
  void initState(){super.initState();_load();}
  Future<void> _load()async{
    try{final tasks=await ToolsDatabase.instance.loadMaintenance(toolId:widget.toolId);
      final tool=widget.toolId==null?null:await ToolsDatabase.instance.loadTool(widget.toolId!);
      if(mounted)setState((){_tasks=tasks;_tool=tool;_loading=false;_error=null;});
    }catch(error){if(mounted)setState((){_error='$error';_loading=false;});}
  }
  Future<void> _add()async{
    final tool=_tool??await chooseManagedTool(context);
    if(tool==null || !mounted)return;
    await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>MaintenanceEditorPage(tool:tool)));
    if(mounted)await _load();
  }
  Future<void> _service(bool value)async{
    if(_tool==null)return;
    String notes=_tool!.serviceNotes;
    if(value){final input=await askManagementText(context,'Motivo / observaciones',initial:notes);
      if(input==null)return;notes=input;}
    try{await ToolsDatabase.instance.setOutOfService(_tool!.id,value,notes);await _load();}
    catch(error){if(mounted)managementError(context,error);}
  }
  @override
  Widget build(BuildContext context){
    final visible=_tasks.where((t)=>_view==2||(_view==1?t.isOverdue:t.enabled)).toList();
    return Scaffold(appBar:AppBar(title:Text(widget.toolName==null?'Mantenimientos':'Mantenimiento · ${widget.toolName}')),
      floatingActionButton:FloatingActionButton(tooltip:'Añadir mantenimiento',onPressed:_add,child:const Icon(Icons.add)),
      body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?
        Center(child:TextButton(onPressed:_load,child:const Text('Reintentar carga'))):ListView(
        padding:const EdgeInsets.fromLTRB(16,16,16,100),children:[
        if(_tool!=null)SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,
          secondary:Icon(Icons.build_outlined,color:_tool!.outOfService?Colors.red:managementColor),
          title:const Text('Fuera de servicio'),subtitle:Text(_tool!.outOfService?
            (_tool!.serviceNotes.isEmpty?'No se permiten nuevos préstamos':_tool!.serviceNotes):'Disponible para usar o prestar'),
          value:_tool!.outOfService,onChanged:_service),
        Wrap(spacing:8,runSpacing:4,children:[for(var i=0;i<3;i++)ChoiceChip(
          label:Text(const['Pendientes','Vencidos','Todos'][i]),selected:_view==i,onSelected:(_)=>setState(()=>_view=i))]),
        const SizedBox(height:12),
        if(visible.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No hay tareas en esta vista. Añade una con +.')),
        for(final task in visible)Card(child:ListTile(
          leading:Icon(task.enabled?Icons.build_outlined:Icons.task_alt,color:task.isOverdue?Colors.deepOrange:managementColor),
          title:Text(task.title),subtitle:Text('${widget.toolId==null?'${task.toolName} · ':''}'
            '${task.enabled?loanDateText(task.dueOn):'Realizada / pausada'}'
            '${task.interval==0?'':' · cada ${task.interval} ${task.intervalUnit}'}'),
          trailing:const Icon(Icons.chevron_right),onTap:()async{
            await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>MaintenanceDetailsPage(task:task)));
            if(mounted)await _load();})),
      ]));
  }
}

Future<String?> askManagementText(BuildContext context,String title,{String initial=''})async{
  final controller=TextEditingController(text:initial);
  final result=await showDialog<String>(context:context,builder:(_)=>AlertDialog(title:Text(title),
    content:TextField(controller:controller,minLines:2,maxLines:6),actions:[
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),
      FilledButton(onPressed:()=>Navigator.pop(context,controller.text.trim()),child:const Text('Guardar'))]));
  // The dialog's reverse transition finishes before disposing its controller.
  Future<void>.delayed(const Duration(milliseconds:300),controller.dispose);
  return result;
}

class MaintenanceEditorPage extends StatefulWidget{
  const MaintenanceEditorPage({super.key,required this.tool,this.initial});
  final ToolItem tool;final MaintenanceTask? initial;
  @override
  State<MaintenanceEditorPage> createState()=>_MaintenanceEditorPageState();
}
class _MaintenanceEditorPageState extends State<MaintenanceEditorPage>{
  final _form=GlobalKey<FormState>();final _title=TextEditingController();final _notes=TextEditingController();
  final _interval=TextEditingController(text:'0');DateTime _date=loanDay(DateTime.now());
  String _unit='meses';int _reminder=1;bool _enabled=true;bool _saving=false;
  @override
  void initState(){super.initState();final t=widget.initial;if(t!=null){_title.text=t.title;_notes.text=t.notes;
    _interval.text='${t.interval}';_unit=t.intervalUnit;_date=t.dueOn;_reminder=t.reminderDays;_enabled=t.enabled;}}
  @override
  void dispose(){_title.dispose();_notes.dispose();_interval.dispose();super.dispose();}
  Future<void> _datePicker()async{
    final result=await showDatePicker(context:context,initialDate:_date,firstDate:DateTime(1900),lastDate:DateTime(2200));
    if(result!=null&&mounted)setState(()=>_date=result);
  }
  Future<void> _save()async{
    if(_saving||!(_form.currentState?.validate()??false))return;setState(()=>_saving=true);
    try{await ToolsDatabase.instance.saveMaintenance(MaintenanceTask(id:widget.initial?.id,
      toolId:widget.tool.id,title:_title.text,dueOn:_date,interval:int.parse(_interval.text),intervalUnit:_unit,
      notes:_notes.text,reminderDays:_reminder,enabled:_enabled));if(mounted)Navigator.pop(context,true);
    }catch(error){if(mounted){managementError(context,error);setState(()=>_saving=false);}}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.initial==null?'Nuevo mantenimiento':'Editar mantenimiento')),
    body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(16),children:[
      Text(widget.tool.name,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700)),const SizedBox(height:16),
      TextFormField(key:const ValueKey('maintenance_title'),controller:_title,
        decoration:const InputDecoration(labelText:'Tarea*',prefixIcon:Icon(Icons.build_outlined)),
        validator:(v)=>v==null||v.trim().isEmpty?'Escribe la tarea':null),const SizedBox(height:12),
      OutlinedButton.icon(onPressed:_datePicker,icon:const Icon(Icons.event_outlined),label:Text('Fecha prevista: ${loanDateText(_date)}')),
      const SizedBox(height:12),TextFormField(controller:_interval,keyboardType:TextInputType.number,
        decoration:const InputDecoration(labelText:'Repetir cada',helperText:'0 = intervención puntual'),
        validator:(v){final n=int.tryParse(v??'');return n==null||n<0||n>10000?'Indica un número entre 0 y 10000':null;}),
      const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:_unit,
        decoration:const InputDecoration(labelText:'Periodicidad'),items:const[
          DropdownMenuItem(value:'meses',child:Text('Meses')),DropdownMenuItem(value:'días',child:Text('Días'))],
        onChanged:(v){if(v!=null)setState(()=>_unit=v);}),const SizedBox(height:12),
      ReminderSelector(value:_reminder,onChanged:(v)=>_reminder=v),const SizedBox(height:12),
      TextFormField(controller:_notes,minLines:2,maxLines:6,decoration:const InputDecoration(labelText:'Observaciones / instrucciones')),
      SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,title:const Text('Tarea activa'),value:_enabled,onChanged:(v)=>setState(()=>_enabled=v)),
      const SizedBox(height:12),FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.check),label:const Text('Guardar mantenimiento')),
    ])));
}

class MaintenanceDetailsPage extends StatefulWidget{
  const MaintenanceDetailsPage({super.key,required this.task});final MaintenanceTask task;
  @override
  State<MaintenanceDetailsPage> createState()=>_MaintenanceDetailsPageState();
}
class _MaintenanceDetailsPageState extends State<MaintenanceDetailsPage>{
  late MaintenanceTask _task;List<MaintenanceRecord> _records=[];bool _loading=true;
  @override
  void initState(){super.initState();_task=widget.task;_load();}
  Future<void> _load()async{
    try{final tasks=await ToolsDatabase.instance.loadMaintenance(toolId:_task.toolId);
      final records=await ToolsDatabase.instance.maintenanceRecords(_task.id!);
      if(mounted)setState((){_task=tasks.firstWhere((t)=>t.id==_task.id);_records=records;_loading=false;});
    }catch(error){if(mounted)managementError(context,error);}
  }
  Future<void> _edit()async{
    final tool=await ToolsDatabase.instance.loadTool(_task.toolId);if(tool==null||!mounted)return;
    await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>MaintenanceEditorPage(tool:tool,initial:_task)));
    if(mounted)await _load();
  }
  Future<void> _record([MaintenanceRecord? record])async{
    await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>MaintenanceRecordPage(task:_task,initial:record)));
    if(mounted)await _load();
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(_task.title),actions:[
    IconButton(tooltip:'Editar tarea',onPressed:_edit,icon:const Icon(Icons.edit_outlined))]),
    body:_loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      Text(_task.toolName,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700)),
      Text(_task.enabled?'Próxima: ${loanDateText(_task.dueOn)}':'Tarea realizada / pausada'),
      if(_task.interval>0)Text('Cada ${_task.interval} ${_task.intervalUnit}'),
      if(_task.notes.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_task.notes)),
      const SizedBox(height:12),FilledButton.icon(onPressed:()=>_record(),icon:const Icon(Icons.task_alt),label:const Text('Registrar intervención')),
      OutlinedButton.icon(onPressed:()=>Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>DocumentsPage(
        toolId:_task.toolId,toolName:_task.title,taskId:_task.id,defaultKind:'Mantenimiento'))),
        icon:const Icon(Icons.attach_file),label:const Text('Documentos / fotografías')),
      const SizedBox(height:20),const SectionTitle('Historial de mantenimiento'),
      if(_records.isEmpty)const Padding(padding:EdgeInsets.only(top:12),child:Text('Sin intervenciones registradas')),
      for(final record in _records)Card(child:ListTile(leading:const Icon(Icons.history),
        title:Text(loanDateText(record.date)),subtitle:Text([record.notes,record.parts,
          if(record.cost>0)'${record.cost.toStringAsFixed(2)} €'].where((s)=>s.isNotEmpty).join('\n')),
        trailing:const Icon(Icons.edit_outlined),onTap:()=>_record(record))),
    ]));
}

class MaintenanceRecordPage extends StatefulWidget{
  const MaintenanceRecordPage({super.key,required this.task,this.initial});
  final MaintenanceTask task;final MaintenanceRecord? initial;
  @override
  State<MaintenanceRecordPage> createState()=>_MaintenanceRecordPageState();
}
class _MaintenanceRecordPageState extends State<MaintenanceRecordPage>{
  final _form=GlobalKey<FormState>();final _notes=TextEditingController();final _parts=TextEditingController();
  final _cost=TextEditingController();DateTime _date=loanDay(DateTime.now());bool _saving=false;
  @override
  void initState(){super.initState();final r=widget.initial;if(r!=null){_date=r.date;_notes.text=r.notes;_parts.text=r.parts;_cost.text='${r.cost}';}}
  @override
  void dispose(){_notes.dispose();_parts.dispose();_cost.dispose();super.dispose();}
  Future<void> _pickDate()async{
    final date=await showDatePicker(context:context,initialDate:_date,firstDate:DateTime(1900),lastDate:loanDay(DateTime.now()));
    if(date!=null&&mounted)setState(()=>_date=date);
  }
  Future<void> _save()async{
    if(_saving||!(_form.currentState?.validate()??false))return;setState(()=>_saving=true);
    try{await ToolsDatabase.instance.saveMaintenanceRecord(MaintenanceRecord(id:widget.initial?.id,
      taskId:widget.task.id!,date:_date,notes:_notes.text,parts:_parts.text,
      cost:double.tryParse(_cost.text.replaceAll(',','.'))??0));if(mounted)Navigator.pop(context,true);
    }catch(error){if(mounted){managementError(context,error);setState(()=>_saving=false);}}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.initial==null?'Registrar intervención':'Editar intervención')),
    body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(16),children:[
      Text(widget.task.title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700)),
      const SizedBox(height:12),OutlinedButton.icon(onPressed:_pickDate,icon:const Icon(Icons.today_outlined),label:Text(loanDateText(_date))),
      const SizedBox(height:12),TextFormField(controller:_notes,minLines:2,maxLines:6,decoration:const InputDecoration(labelText:'Trabajo realizado / observaciones')),
      const SizedBox(height:12),TextFormField(controller:_parts,decoration:const InputDecoration(labelText:'Piezas sustituidas')),
      const SizedBox(height:12),TextFormField(controller:_cost,keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:const InputDecoration(labelText:'Coste (€), opcional'),validator:(v){if(v==null||v.isEmpty)return null;
          final n=double.tryParse(v.replaceAll(',','.'));return n==null||!n.isFinite||n<0?'Coste no válido':null;}),
      const SizedBox(height:24),FilledButton.icon(onPressed:_saving?null:_save,icon:const Icon(Icons.check),label:const Text('Guardar intervención')),
    ])));
}

class LoanDetailsPage extends StatefulWidget{
  const LoanDetailsPage({super.key,required this.loan});final ToolLoan loan;
  @override
  State<LoanDetailsPage> createState()=>_LoanDetailsPageState();
}
class _LoanDetailsPageState extends State<LoanDetailsPage>{
  late ToolLoan _loan;List<LoanContent> _contents=[];List<Map<String,Object?>> _events=[];
  bool _loading=true;String? _error;
  @override
  void initState(){super.initState();_loan=widget.loan;_load();}
  Future<void> _load()async{
    try{final loans=await ToolsDatabase.instance.loadLoans(toolId:_loan.toolId);
      final contents=await ToolsDatabase.instance.loadLoanContents(_loan.id);
      final events=await ToolsDatabase.instance.loanEvents(_loan.id);
      if(mounted)setState((){_loan=loans.firstWhere((l)=>l.id==_loan.id);_contents=contents;_events=events;_loading=false;_error=null;});
    }catch(error){if(mounted)setState((){_error='$error';_loading=false;});}
  }
  Future<void> _edit()async{
    await Navigator.push<LoanDraft>(context,MaterialPageRoute(builder:(_)=>LoanFormPage(
      toolName:_loan.toolName,quantity:_loan.quantity,unit:_loan.unit,initialLoan:_loan,toolId:_loan.toolId)));
    if(mounted)await _load();
  }
  Future<void> _return()async{
    await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>ManagedReturnPage(loan:_loan,contents:_contents)));
    if(mounted)await _load();
  }
  Future<void> _event(Map<String,Object?> event)async{
    final value=await askManagementText(context,'Observaciones de ${event['kind']}',initial:event['notes'] as String);
    if(value==null||!mounted)return;
    try{await ToolsDatabase.instance.editLoanEvent(event['id'] as int,value,event['condition'] as String);await _load();}
    catch(error){if(mounted)managementError(context,error);}
  }
  Future<void> _docs(String kind)async{
    await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>DocumentsPage(toolId:_loan.toolId,
      toolName:_loan.toolName,loanId:_loan.id,defaultKind:kind)));
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Detalle del préstamo'),actions:[
    IconButton(tooltip:'Editar préstamo',onPressed:_edit,icon:const Icon(Icons.edit_outlined))]),
    body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?
      Center(child:TextButton(onPressed:_load,child:const Text('Reintentar carga'))):ListView(padding:const EdgeInsets.all(16),children:[
      Text(_loan.toolName,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.person_outline),title:Text(_loan.borrower),
        subtitle:_loan.contact.isEmpty?null:Text(_loan.contact)),
      Text('Entrega: ${loanDateText(_loan.startedOn)}'),
      Text(_loan.dueOn==null?'Sin fecha prevista':'Devolución prevista: ${loanDateText(_loan.dueOn!)}'),
      if(_loan.returnedOn!=null)Text('Devuelto: ${loanDateText(_loan.returnedOn!)}'),
      if(_loan.isOverdue)const Text('Devolución atrasada',style:TextStyle(color:Colors.deepOrange,fontWeight:FontWeight.w700)),
      if(_loan.quantity>0)Text('Prestado: ${formatNumber(_loan.quantity)} ${_loan.unit} · pendiente: ${formatNumber(_loan.pendingQuantity)}'),
      if(_loan.deliveryCondition.isNotEmpty)Text('Estado de entrega: ${_loan.deliveryCondition}'),
      if(_loan.accessories.isNotEmpty)Text('Accesorios: ${_loan.accessories}'),
      if(_loan.notes.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_loan.notes)),
      if(_contents.isNotEmpty)...[
        const SizedBox(height:16),const SectionTitle('Contenido entregado'),
        for(final c in _contents)ListTile(contentPadding:EdgeInsets.zero,
          leading:Icon(c.pending<=0?Icons.check_circle_outline:Icons.extension_outlined,color:c.pending<=0?Colors.green:managementColor),
          title:Text(c.name),subtitle:Text('${formatNumber(c.quantity)} entregadas · ${formatNumber(c.pending)} pendientes')),
      ],
      if(_loan.isActive)FilledButton.icon(key:const ValueKey('record_partial_return'),onPressed:_return,
        icon:const Icon(Icons.assignment_turned_in_outlined),label:const Text('Registrar devolución')),
      OutlinedButton.icon(onPressed:_edit,icon:const Icon(Icons.edit_outlined),label:const Text('Editar préstamo')),
      OutlinedButton.icon(onPressed:()=>_docs(_loan.isActive?'Entrega':'Devolución'),
        icon:const Icon(Icons.attach_file),label:const Text('Documentos / fotos de entrega y devolución')),
      const SizedBox(height:20),const SectionTitle('Historial de cambios y devoluciones'),
      if(_events.isEmpty)const Padding(padding:EdgeInsets.only(top:12),child:Text('Sin cambios registrados')),
      for(final event in _events)Card(child:ListTile(
        leading:Icon(event['kind']=='Devolución'?Icons.assignment_turned_in_outlined:event['kind']=='Entrega'?Icons.handshake_outlined:Icons.history),
        title:Text('${event['kind']} · ${loanDateText(DateTime.parse(event['performed_on'] as String? ?? event['created_at'] as String))}'),
        subtitle:Text([event['details'] as String,event['condition'] as String,event['notes'] as String].where((s)=>s.isNotEmpty).join('\n')),
        trailing:const Icon(Icons.edit_outlined),onTap:()=>_event(event))),
    ]));
}

class ManagedReturnPage extends StatefulWidget{
  const ManagedReturnPage({super.key,required this.loan,required this.contents});
  final ToolLoan loan;final List<LoanContent> contents;
  @override
  State<ManagedReturnPage> createState()=>_ManagedReturnPageState();
}
class _ManagedReturnPageState extends State<ManagedReturnPage>{
  final _form=GlobalKey<FormState>();final _quantity=TextEditingController();final _notes=TextEditingController();
  final _condition=TextEditingController();final _parts=<int,TextEditingController>{};
  DateTime _date=loanDay(DateTime.now());bool _maintenance=false;bool _saving=false;
  @override
  void initState(){super.initState();_quantity.text=formatNumber(widget.loan.pendingQuantity);
    for(final c in widget.contents){_parts[c.id]=TextEditingController(text:formatNumber(c.pending));}}
  @override
  void dispose(){_quantity.dispose();_notes.dispose();_condition.dispose();for(final c in _parts.values){c.dispose();}super.dispose();}
  String? _validate(String? text,double maximum){
    final n=double.tryParse((text??'').replaceAll(',','.'));
    return n==null||!n.isFinite||n<0||n>maximum+0.000001?'Indica entre 0 y ${formatNumber(maximum)}':null;
  }
  Future<void> _pickDate()async{
    final date=await showDatePicker(context:context,initialDate:_date,firstDate:loanDay(widget.loan.startedOn),lastDate:loanDay(DateTime.now()));
    if(date!=null&&mounted)setState(()=>_date=date);
  }
  Future<void> _save()async{
    if(_saving||!(_form.currentState?.validate()??false))return;setState(()=>_saving=true);
    try{await ToolsDatabase.instance.recordReturn(widget.loan.id,LoanReturnDraft(date:_date,
      quantity:double.tryParse(_quantity.text.replaceAll(',','.')),
      contents:{for(final c in widget.contents)c.id:double.parse(_parts[c.id]!.text.replaceAll(',','.'))},
      notes:_notes.text,condition:_condition.text,needsMaintenance:_maintenance));
      if(mounted)Navigator.pop(context,true);
    }catch(error){if(mounted){managementError(context,error);setState(()=>_saving=false);}}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Registrar devolución')),
    body:Form(key:_form,child:ListView(padding:const EdgeInsets.all(16),children:[
      Text('${widget.loan.toolName} · ${widget.loan.borrower}',style:const TextStyle(fontWeight:FontWeight.w700,fontSize:18)),
      const SizedBox(height:12),OutlinedButton.icon(onPressed:_pickDate,icon:const Icon(Icons.event_available_outlined),label:Text(loanDateText(_date))),
      const SizedBox(height:12),
      if(widget.contents.isEmpty)TextFormField(key:const ValueKey('return_quantity'),controller:_quantity,
        keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:'Cantidad devuelta (${widget.loan.unit})',helperText:'Pendiente: ${formatNumber(widget.loan.pendingQuantity)}'),
        validator:(v)=>_validate(v,widget.loan.pendingQuantity))
      else ...[
        const Text('Indica las piezas que vuelven ahora. Pon 0 en las que siguen prestadas.'),const SizedBox(height:12),
        for(final c in widget.contents)Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(
          key:ValueKey('return_piece_${c.id}'),controller:_parts[c.id],keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:InputDecoration(labelText:c.name,helperText:'Pendientes: ${formatNumber(c.pending)}'),validator:(v)=>_validate(v,c.pending))),
      ],
      const SizedBox(height:12),TextFormField(controller:_condition,decoration:const InputDecoration(labelText:'Estado al devolver (opcional)',prefixIcon:Icon(Icons.fact_check_outlined))),
      const SizedBox(height:12),TextFormField(controller:_notes,minLines:2,maxLines:6,decoration:const InputDecoration(labelText:'Observaciones de devolución')),
      SwitchListTile.adaptive(contentPadding:EdgeInsets.zero,secondary:const Icon(Icons.build_outlined),
        title:const Text('Necesita mantenimiento'),subtitle:const Text('Las unidades o piezas devueltas quedarán fuera de servicio'),
        value:_maintenance,onChanged:(v)=>setState(()=>_maintenance=v)),
      const SizedBox(height:16),const Text('El préstamo seguirá abierto mientras quede algo por devolver.'),
      const SizedBox(height:16),FilledButton.icon(key:const ValueKey('confirm_partial_return'),onPressed:_saving?null:_save,
        icon:const Icon(Icons.check),label:const Text('Guardar devolución')),
    ])));
}
