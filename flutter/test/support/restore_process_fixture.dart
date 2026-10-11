// Synthetic fixtures only. Never point this helper at an installed inventory.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../lib/main_quill_integrated_test.dart';

class RestoreProcessFixture {
  RestoreProcessFixture(this.root);
  final Directory root;
  late Directory active;
  Future<void> location(String name) async {
    await ToolsDatabase.instance.closeForBackup();
    active = Directory('${root.path}/$name');
    await active.create(recursive: true);
    await databaseFactory.setDatabasesPath('${active.path}/db');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => active.path,
        );
    SafeRestore.resetRuntimeForTest();
  }

  Future<void> seed(String name) async {
    final images = Directory('${active.path}/tool_images/custom_icons');
    await images.create(recursive: true);
    await File(
      '${active.path}/tool_images/photo.jpg',
    ).writeAsString('photo-$name:${'p' * (512 * 1024)}');
    await File('${images.path}/icon.svg').writeAsString(
      '<svg xmlns="http://www.w3.org/2000/svg"><!--$name:${'s' * (128 * 1024)}--></svg>',
    );
    await File(
      '${images.path}/icon.svg.group.json',
    ).writeAsString('{"group":"Mis iconos"}');
    await File(
      '${active.path}/tool_images/icon_names.json',
    ).writeAsString('{"custom:icon.svg":"Alias-$name"}');
    await File(
      '${active.path}/tool_images/icon_settings.json',
    ).writeAsString('{"favorites":["custom:icon.svg"],"appearances":{}}');
    await ToolsDatabase.instance.saveTool(
      ToolItem(
        id: 1,
        name: 'Conjunto-$name',
        description: '',
        descriptionDelta: '',
        barcode: '',
        quantity: 1,
        unit: 'ud',
        minimumStock: 0,
        purchasePrice: 0,
        condition: 'Bueno',
        isSet: true,
        locationSite: 'Taller-$name',
        images: [
          ToolImage(
            toolId: 1,
            path: '${active.path}/tool_images/photo.jpg',
            isPrimary: true,
          ),
        ],
      ),
    );
    await ToolsDatabase.instance.saveTool(
      ToolItem(
        id: 2,
        name: 'Pieza-$name',
        description: '',
        descriptionDelta: '',
        barcode: '',
        quantity: 3,
        unit: 'ud',
        minimumStock: 0,
        purchasePrice: 0,
        condition: 'Bueno',
        parentId: 1,
      ),
    );
    await ToolsDatabase.instance.saveTool(
      ToolItem(
        id: 3,
        name: 'Papelera-$name',
        description: '',
        descriptionDelta: '',
        barcode: '',
        quantity: 1,
        unit: 'ud',
        minimumStock: 0,
        purchasePrice: 0,
        condition: 'Bueno',
      ),
    );
    await ToolsDatabase.instance.trashTool(3);
    final kit = (await ToolsDatabase.instance.loadTool(1))!;
    kit.loanDraft = LoanDraft(
      borrower: 'Persona-$name',
      startedOn: DateTime(2026, 1, 1),
    );
    await ToolsDatabase.instance.saveTool(kit);
    final task = await ToolsDatabase.instance.saveMaintenance(
      MaintenanceTask(
        toolId: 1,
        title: 'Mantenimiento-$name',
        dueOn: DateTime(2026, 6, 1),
      ),
    );
    await ToolsDatabase.instance.saveMaintenanceRecord(
      MaintenanceRecord(
        taskId: task,
        date: DateTime(2026, 1, 2),
        notes: 'Intervención-$name',
        cost: 10,
      ),
    );
    final documents = await toolDocumentsDirectory();
    await File(
      '${documents.path}/manual.pdf',
    ).writeAsString('document-$name:${'d' * (256 * 1024)}');
    await ToolsDatabase.instance.saveDocument(
      ToolDocument(
        toolId: 1,
        taskId: task,
        name: 'Manual-$name',
        fileName: 'manual.pdf',
      ),
    );
    await (await ToolsDatabase.instance.database).insert('field_options', {
      'field_key': 'type',
      'label': 'Tipo-$name',
      'icon_key': 'custom:${images.path}/icon.svg',
      'color_value': 0xff123456,
      'position': 25,
    });
    await saveInventoryPreferences(
      const InventoryPreferences(view: InventoryView.grid),
    );
  }
}
