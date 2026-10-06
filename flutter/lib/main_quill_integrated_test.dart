import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const GestorHerramientasApp());
}

class GestorHerramientasApp extends StatelessWidget {
  const GestorHerramientasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gestor Quill Integrado',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF168BD2),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEAF4FE),
          foregroundColor: Color(0xFF20242A),
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFD7DDE3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFD7DDE3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF168BD2), width: 2),
          ),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en')],
      home: const ToolsHomePage(),
    );
  }
}

class ToolImage {
  ToolImage({
    this.id,
    required this.toolId,
    required this.path,
    this.description = '',
    this.type = 'General',
    this.position = 0,
    this.isPrimary = false,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  int? id;
  int toolId;
  String path;
  String description;
  String type;
  int position;
  bool isPrimary;
  String createdAt;

  ToolImage copy() => ToolImage(
    id: id,
    toolId: toolId,
    path: path,
    description: description,
    type: type,
    position: position,
    isPrimary: isPrimary,
    createdAt: createdAt,
  );

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'tool_id': toolId,
      'path': path,
      'description': description,
      'type': type,
      'position': position,
      'is_primary': isPrimary ? 1 : 0,
      'created_at': createdAt,
    };
    if (includeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory ToolImage.fromMap(Map<String, Object?> map) => ToolImage(
    id: map['id'] as int?,
    toolId: (map['tool_id'] as num?)?.toInt() ?? 0,
    path: (map['path'] as String?) ?? '',
    description: (map['description'] as String?) ?? '',
    type: (map['type'] as String?) ?? 'General',
    position: (map['position'] as num?)?.toInt() ?? 0,
    isPrimary: ((map['is_primary'] as num?)?.toInt() ?? 0) == 1,
    createdAt: (map['created_at'] as String?) ?? '',
  );
}

class AppIconChoice {
  const AppIconChoice(
    this.key,
    this.label,
    this.icon,
    this.category,
    this.defaultColorValue,
  );

  final String key;
  final String label;
  final IconData icon;
  final String category;
  final int defaultColorValue;

  Color get defaultColor => Color(defaultColorValue);
}

const appIconCategories = <String>[
  'Todos',
  'Mis iconos',
  'Herramientas',
  'Eléctrica',
  'Material',
  'Estado',
  'General',
];

const appIconChoices = <AppIconChoice>[
  // Colección vectorial de 50 iconos disponibles sin importar archivos.
  AppIconChoice(
    'electric_enchufe_schuko',
    'Enchufe Schuko',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_bombilla',
    'Bombilla',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_cuadro_electrico',
    'Cuadro eléctrico',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_conexion',
    'Conexión',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_energia_renovable',
    'Energía renovable',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_ahorro_energia',
    'Ahorro de energía',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_casa_conectada',
    'Casa conectada',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_regleta',
    'Regleta',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_calentador',
    'Calentador',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_alicates',
    'Alicates',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_sobretension',
    'Sobretensión',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_distribuidor',
    'Distribuidor',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_clavija_circular',
    'Clavija circular',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_cambio_bombilla',
    'Cambio de bombilla',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_clavija',
    'Clavija',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_bombilla_bajo_consumo',
    'Bajo consumo',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_transformador',
    'Transformador',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_torre_alta_tension',
    'Torre de alta tensión',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_medidor',
    'Medidor',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_alicates_corte',
    'Alicates de corte',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_proteccion_personal',
    'Protección personal',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_consumo_electrico',
    'Consumo eléctrico',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_cargador_vehiculo',
    'Cargador de vehículo',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_cable_alimentacion',
    'Cable de alimentación',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_tubo_led',
    'Tubo LED',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_conector',
    'Conector',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_seguridad_electrica',
    'Seguridad eléctrica',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_casa_electrica',
    'Casa eléctrica',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_coche_electrico',
    'Coche eléctrico',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_foco',
    'Foco',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_poste_electrico',
    'Poste eléctrico',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_red_transporte',
    'Red de transporte',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_eficiencia_energetica',
    'Eficiencia energética',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_cable_multiconductor',
    'Cable multiconductor',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_toma_empotrada',
    'Toma empotrada',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_magnetotermicos',
    'Magnetotérmicos',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_bateria',
    'Batería',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_toma_doble',
    'Toma doble',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_lampara_colgante',
    'Lámpara colgante',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_enchufe_cuadrado',
    'Enchufe cuadrado',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_caja_herramientas',
    'Caja de herramientas',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_bombilla_led',
    'Bombilla LED',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_electricista',
    'Electricista',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_herramientas',
    'Herramientas',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),
  AppIconChoice(
    'electric_cable_enrollado',
    'Cable enrollado',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF42954A,
  ),
  AppIconChoice(
    'electric_cable_danado',
    'Cable dañado',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFCD4945,
  ),
  AppIconChoice(
    'electric_multimetro',
    'Multímetro',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF6350A5,
  ),
  AppIconChoice(
    'electric_peligro_electrico',
    'Peligro eléctrico',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF087F80,
  ),
  AppIconChoice(
    'electric_casa_encendido',
    'Casa encendida',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFF34688B,
  ),
  AppIconChoice(
    'electric_interruptor',
    'Interruptor',
    Icons.electrical_services_outlined,
    'Mis iconos',
    0xFFE6A12B,
  ),

  // Herramientas
  AppIconChoice(
    'tool_art_hammer',
    'Martillo',
    Icons.hardware_outlined,
    'Herramientas',
    0xFF455A64,
  ),
  AppIconChoice(
    'tool_art_handsaw',
    'Sierra de mano',
    Icons.carpenter_outlined,
    'Herramientas',
    0xFFF57C00,
  ),
  AppIconChoice(
    'tool_art_screwdriver',
    'Destornillador',
    Icons.build_outlined,
    'Herramientas',
    0xFFE53935,
  ),
  AppIconChoice(
    'tool_art_drill',
    'Taladro',
    Icons.precision_manufacturing_outlined,
    'Herramientas',
    0xFF1976D2,
  ),
  AppIconChoice(
    'handyman',
    'Herramientas',
    Icons.handyman_outlined,
    'Herramientas',
    0xFF1976D2,
  ),
  AppIconChoice(
    'construction',
    'Construcción',
    Icons.construction_outlined,
    'Herramientas',
    0xFFF57C00,
  ),
  AppIconChoice(
    'build_tool',
    'Reparación',
    Icons.build_outlined,
    'Herramientas',
    0xFF546E7A,
  ),
  AppIconChoice(
    'repair_service',
    'Servicio',
    Icons.home_repair_service_outlined,
    'Herramientas',
    0xFF6D4C41,
  ),
  AppIconChoice(
    'hardware',
    'Ferretería',
    Icons.hardware_outlined,
    'Herramientas',
    0xFF455A64,
  ),
  AppIconChoice(
    'plumbing',
    'Tubería',
    Icons.plumbing_outlined,
    'Herramientas',
    0xFF00838F,
  ),
  AppIconChoice(
    'precision',
    'Precisión',
    Icons.precision_manufacturing_outlined,
    'Herramientas',
    0xFF5E35B1,
  ),
  AppIconChoice(
    'engineering',
    'Ingeniería',
    Icons.engineering_outlined,
    'Herramientas',
    0xFF3949AB,
  ),
  AppIconChoice(
    'straighten',
    'Medida',
    Icons.straighten_outlined,
    'Herramientas',
    0xFF00897B,
  ),
  AppIconChoice(
    'speed',
    'Medición',
    Icons.speed_outlined,
    'Herramientas',
    0xFF3949AB,
  ),

  // Eléctrica
  AppIconChoice(
    'electrical',
    'Eléctrica',
    Icons.electrical_services_outlined,
    'Eléctrica',
    0xFFF9A825,
  ),
  AppIconChoice('bolt', 'Rayo', Icons.bolt_outlined, 'Eléctrica', 0xFFFDD835),
  AppIconChoice(
    'power',
    'Potencia',
    Icons.power_outlined,
    'Eléctrica',
    0xFFE53935,
  ),
  AppIconChoice(
    'cable',
    'Cable',
    Icons.cable_outlined,
    'Eléctrica',
    0xFF3949AB,
  ),
  AppIconChoice(
    'battery',
    'Batería',
    Icons.battery_charging_full_outlined,
    'Eléctrica',
    0xFF43A047,
  ),
  AppIconChoice(
    'lightbulb',
    'Iluminación',
    Icons.lightbulb_outline,
    'Eléctrica',
    0xFFFBC02D,
  ),
  AppIconChoice(
    'memory',
    'Electrónica',
    Icons.memory_outlined,
    'Eléctrica',
    0xFF7E57C2,
  ),
  AppIconChoice(
    'sensors',
    'Sensor',
    Icons.sensors_outlined,
    'Eléctrica',
    0xFF00897B,
  ),
  AppIconChoice(
    'developer_board',
    'Placa',
    Icons.developer_board_outlined,
    'Eléctrica',
    0xFF5E35B1,
  ),
  AppIconChoice(
    'wifi_signal',
    'Señal',
    Icons.wifi_tethering,
    'Eléctrica',
    0xFF039BE5,
  ),

  // Material
  AppIconChoice(
    'inventory',
    'Inventario',
    Icons.inventory_2_outlined,
    'Material',
    0xFF00897B,
  ),
  AppIconChoice(
    'settings',
    'Engranaje',
    Icons.settings_outlined,
    'Material',
    0xFF7E57C2,
  ),
  AppIconChoice(
    'package',
    'Paquete',
    Icons.all_inbox_outlined,
    'Material',
    0xFF6D4C41,
  ),
  AppIconChoice(
    'extension',
    'Pieza',
    Icons.extension_outlined,
    'Material',
    0xFF5E35B1,
  ),
  AppIconChoice(
    'widgets',
    'Componentes',
    Icons.widgets_outlined,
    'Material',
    0xFF3949AB,
  ),
  AppIconChoice(
    'category',
    'Categoría',
    Icons.category_outlined,
    'Material',
    0xFF1976D2,
  ),
  AppIconChoice(
    'science',
    'Química',
    Icons.science_outlined,
    'Material',
    0xFF8E24AA,
  ),
  AppIconChoice(
    'water',
    'Líquido',
    Icons.water_drop_outlined,
    'Material',
    0xFF039BE5,
  ),
  AppIconChoice(
    'local_fire',
    'Calor',
    Icons.local_fire_department_outlined,
    'Material',
    0xFFEF6C00,
  ),
  AppIconChoice(
    'cleaning',
    'Limpieza',
    Icons.cleaning_services_outlined,
    'Material',
    0xFF00ACC1,
  ),
  AppIconChoice(
    'recycling',
    'Reciclable',
    Icons.recycling_outlined,
    'Material',
    0xFF43A047,
  ),
  AppIconChoice(
    'delete_sweep',
    'Desechable',
    Icons.delete_sweep_outlined,
    'Material',
    0xFFE53935,
  ),
  AppIconChoice(
    'factory',
    'Industrial',
    Icons.factory_outlined,
    'Material',
    0xFF546E7A,
  ),

  // Estado
  AppIconChoice(
    'check',
    'Correcto',
    Icons.check_circle_outline,
    'Estado',
    0xFF43A047,
  ),
  AppIconChoice(
    'build',
    'Revisión',
    Icons.build_circle_outlined,
    'Estado',
    0xFFF9A825,
  ),
  AppIconChoice('error', 'Avería', Icons.error_outline, 'Estado', 0xFFE53935),
  AppIconChoice('swap', 'Préstamo', Icons.swap_horiz, 'Estado', 0xFF7E57C2),
  AppIconChoice(
    'warning',
    'Aviso',
    Icons.warning_amber_outlined,
    'Estado',
    0xFFF57C00,
  ),
  AppIconChoice('blocked', 'Bloqueado', Icons.block, 'Estado', 0xFFE53935),
  AppIconChoice(
    'pause',
    'Pausado',
    Icons.pause_circle_outline,
    'Estado',
    0xFF546E7A,
  ),
  AppIconChoice('schedule', 'Pendiente', Icons.schedule, 'Estado', 0xFF5E35B1),
  AppIconChoice('done_all', 'Finalizado', Icons.done_all, 'Estado', 0xFF00897B),
  AppIconChoice(
    'help',
    'Desconocido',
    Icons.help_outline,
    'Estado',
    0xFF78909C,
  ),

  // General
  AppIconChoice('star', 'Destacado', Icons.star_outline, 'General', 0xFFFBC02D),
  AppIconChoice(
    'favorite',
    'Favorito',
    Icons.favorite_border,
    'General',
    0xFFD81B60,
  ),
  AppIconChoice(
    'label',
    'Etiqueta',
    Icons.label_outline,
    'General',
    0xFF7E57C2,
  ),
  AppIconChoice(
    'bookmark',
    'Marcador',
    Icons.bookmark_border,
    'General',
    0xFF3949AB,
  ),
  AppIconChoice(
    'place',
    'Ubicación',
    Icons.place_outlined,
    'General',
    0xFFE53935,
  ),
  AppIconChoice(
    'info',
    'Información',
    Icons.info_outline,
    'General',
    0xFF1976D2,
  ),
  AppIconChoice(
    'push_pin',
    'Fijado',
    Icons.push_pin_outlined,
    'General',
    0xFFEF6C00,
  ),
  AppIconChoice(
    'person',
    'Persona',
    Icons.person_outline,
    'General',
    0xFF5E35B1,
  ),
  AppIconChoice(
    'groups',
    'Grupo',
    Icons.groups_outlined,
    'General',
    0xFF3949AB,
  ),
  AppIconChoice('event', 'Fecha', Icons.event_outlined, 'General', 0xFF00897B),
  AppIconChoice('qr', 'QR', Icons.qr_code_2, 'General', 0xFF455A64),
  AppIconChoice(
    'camera',
    'Cámara',
    Icons.photo_camera_outlined,
    'General',
    0xFF1976D2,
  ),
  AppIconChoice('attach', 'Adjunto', Icons.attach_file, 'General', 0xFF546E7A),
  AppIconChoice(
    'description',
    'Documento',
    Icons.description_outlined,
    'General',
    0xFF3949AB,
  ),
  AppIconChoice(
    'folder',
    'Carpeta',
    Icons.folder_outlined,
    'General',
    0xFFF9A825,
  ),
  AppIconChoice(
    'shield',
    'Protección',
    Icons.shield_outlined,
    'General',
    0xFF00897B,
  ),
  AppIconChoice('lock', 'Bloqueo', Icons.lock_outline, 'General', 0xFF6D4C41),
];

bool isToolArtworkKey(String key) => const {
  'tool_art_hammer',
  'tool_art_handsaw',
  'tool_art_screwdriver',
  'tool_art_drill',
}.contains(key);

bool isElectricCollectionKey(String key) => appIconChoices.any(
  (choice) => choice.key == key && choice.key.startsWith('electric_'),
);

bool isCustomIconKey(String key) => key.startsWith('custom:');

String customIconPathFromKey(String key) =>
    isCustomIconKey(key) ? key.substring('custom:'.length) : '';

AppIconChoice appIconChoiceFor(String key) {
  return appIconChoices.firstWhere(
    (choice) => choice.key == key,
    orElse: () => appIconChoices.first,
  );
}

IconData appIconFor(String key) =>
    isCustomIconKey(key) ? Icons.image_outlined : appIconChoiceFor(key).icon;

Map<String, String> _iconNameOverrides = {};

String iconNameStorageKey(String key) => isCustomIconKey(key)
    ? 'custom:${p.basename(customIconPathFromKey(key))}'
    : key;

String appIconLabel(String key) =>
    _iconNameOverrides[iconNameStorageKey(key)] ?? defaultAppIconLabel(key);

String defaultAppIconLabel(String key) {
  if (isCustomIconKey(key)) {
    final path = customIconPathFromKey(key);
    final name = p.basenameWithoutExtension(path);
    return name.isEmpty ? 'Icono personalizado' : name;
  }
  return appIconChoiceFor(key).label;
}


bool isEditableSvgIcon(String key) =>
    isCustomIconKey(key) &&
    p.extension(customIconPathFromKey(key)).toLowerCase() == '.svg';

bool canEditIconColors(String key) =>
    isEditableSvgIcon(key) ||
    (!isCustomIconKey(key) && !isToolArtworkKey(key));

bool hasIconCircle(String key) =>
    isElectricCollectionKey(key) || isEditableSvgIcon(key) ||
    (canEditIconColors(key) &&
        _iconAppearances.containsKey(iconNameStorageKey(key)));

class IconAppearance {
  const IconAppearance(this.lineValue, this.circleValue);
  final int lineValue;
  final int circleValue;
  Color get line => Color(lineValue);
  Color get circle => Color(circleValue);
}
Map<String, IconAppearance> _iconAppearances = {};
IconAppearance iconAppearance(String key) =>
    _iconAppearances[iconNameStorageKey(key)] ??
    IconAppearance(
      isCustomIconKey(key) ? 0xFF31678F : appIconChoiceFor(key).defaultColorValue,
      (isCustomIconKey(key) ? const Color(0xFF31678F) :
          appIconChoiceFor(key).defaultColor).withValues(alpha: 0.12).toARGB32(),
    );

class IconSvgColorMapper extends ColorMapper {
  const IconSvgColorMapper(this.lines, this.background);
  final Color lines;
  final Color background;
  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) {
    if (color.a == 0) return color;
    if (id == 'fondo' && attributeName == 'fill') return background;
    return lines;
  }
  @override
  bool operator ==(Object other) => other is IconSvgColorMapper &&
      lines == other.lines && background == other.background;
  @override
  int get hashCode => Object.hash(lines, background);
}

Future<void> saveIconAppearance(String key, IconAppearance appearance) async {
  final updated = Map<String, IconAppearance>.from(_iconAppearances);
  updated[iconNameStorageKey(key)] = appearance;
  await _persistIconSettings(
    hidden: Set<String>.from(_hiddenIconKeys),
    favorites: Set<String>.from(_favoriteIconKeys),
    customGroups: List<String>.from(_customIconCategories),
    groups: Map<String, String>.from(_iconGroupOverrides),
    appearances: updated,
  );
}

Widget iconWidgetForKey(
  String key, {
  required Color color,
  double size = 24,
  BoxFit fit = BoxFit.contain,
  Color? circleColor,
}) {
  if (isElectricCollectionKey(key)) {
    return SvgPicture.asset(
      'assets/icons/electricos/${key.substring('electric_'.length)}.svg',
      width: size,
      height: size,
      fit: fit,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
  if (isToolArtworkKey(key)) {
    // Ventanas de la imagen original: conserva los cuatro dibujos aprobados
    // sin ampliarlos respecto al tamaño que pide cada pantalla.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: Stack(
            children: [
              Positioned(
                left:
                    -const {
                      'tool_art_hammer': 192.0,
                      'tool_art_handsaw': 481.0,
                      'tool_art_screwdriver': 760.0,
                      'tool_art_drill': 1052.0,
                    }[key]! *
                    size /
                    200,
                top: -415 * size / 200,
                width: 1448 * size / 200,
                height: 1086 * size / 200,
                child: Image.asset(
                  'assets/icons/herramientas.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => key == 'tool_art_hammer'
                      ? Icon(Icons.hardware_outlined, color: color, size: size)
                      : _ToolArtworkIcon(kind: key, size: size, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  if (!isCustomIconKey(key)) {
    return Icon(appIconFor(key), color: color, size: size);
  }

  final path = customIconPathFromKey(key);
  final file = File(path);
  if (!file.existsSync()) {
    return Icon(Icons.broken_image_outlined, color: color, size: size);
  }

  final extension = p.extension(path).toLowerCase();
  if (extension == '.svg') {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.file(
        file,
        fit: fit,
        colorMapper: IconSvgColorMapper(color, circleColor ?? iconAppearance(key).circle),
        placeholderBuilder: (_) =>
            Icon(Icons.image_outlined, color: color, size: size),
      ),
    );
  }

  return SizedBox(
    width: size,
    height: size,
    child: Image.file(
      file,
      fit: fit,
      errorBuilder: (_, _, _) =>
          Icon(Icons.broken_image_outlined, color: color, size: size),
    ),
  );
}

Widget fieldOptionIconWidget(FieldOption option, {double size = 24}) {
  final glyph = iconWidgetForKey(
    option.iconKey,
    color: option.color,
    size: hasIconCircle(option.iconKey) ? size * 0.55 : size,
    circleColor: option.circleColor,
  );
  if (!hasIconCircle(option.iconKey)) return glyph;
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: option.circleColor,
      shape: BoxShape.circle,
    ),
    child: glyph,
  );
}

const optionColorPalette = <int>[
  0xFF1976D2,
  0xFF039BE5,
  0xFF00838F,
  0xFF00897B,
  0xFF43A047,
  0xFF7CB342,
  0xFFFBC02D,
  0xFFF9A825,
  0xFFF57C00,
  0xFFEF6C00,
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF7E57C2,
  0xFF5E35B1,
  0xFF3949AB,
  0xFF546E7A,
  0xFF455A64,
  0xFF6D4C41,
  0xFF78909C,
];

class _ToolArtworkIcon extends StatelessWidget {
  const _ToolArtworkIcon({
    required this.kind,
    required this.size,
    required this.color,
  });

  final String kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _ToolArtworkPainter(kind: kind, color: color),
        ),
      ),
    );
  }
}

class _ToolArtworkPainter extends CustomPainter {
  const _ToolArtworkPainter({required this.kind, required this.color});

  final String kind;
  final Color color;

  Paint get _stroke => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    // Misma caja de 24 y trazo de 2 que los iconos Material del catálogo.
    final side = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 24);
    switch (kind) {
      case 'tool_art_handsaw':
        _drawHandSaw(canvas);
      case 'tool_art_screwdriver':
        _drawScrewdriver(canvas);
      case 'tool_art_drill':
        _drawDrill(canvas);
    }
    canvas.restore();
  }

  void _drawHandSaw(Canvas canvas) {
    final blade = Path()
      ..moveTo(3, 9)
      ..lineTo(15, 6)
      ..lineTo(15, 15)
      ..lineTo(13, 17)
      ..lineTo(12, 15)
      ..lineTo(10, 17)
      ..lineTo(9, 15)
      ..lineTo(7, 17)
      ..lineTo(6, 15)
      ..lineTo(4, 17)
      ..close();
    canvas.drawPath(blade, _stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(15, 5, 6, 11),
        const Radius.circular(2),
      ),
      _stroke,
    );
    canvas.drawLine(const Offset(18, 8), const Offset(18, 12), _stroke);
  }

  void _drawScrewdriver(Canvas canvas) {
    final shaft = Path()
      ..moveTo(11, 13)
      ..lineTo(18, 6)
      ..lineTo(19, 3)
      ..lineTo(21, 3)
      ..lineTo(21, 5)
      ..lineTo(18, 6);
    canvas.drawPath(shaft, _stroke);
    final handle = Path()
      ..moveTo(9, 12)
      ..lineTo(12, 15)
      ..quadraticBezierTo(13, 16, 12, 17)
      ..lineTo(8, 21)
      ..quadraticBezierTo(7, 22, 6, 21)
      ..lineTo(3, 18)
      ..quadraticBezierTo(2, 17, 3, 16)
      ..lineTo(7, 12)
      ..quadraticBezierTo(8, 11, 9, 12)
      ..close();
    canvas.drawPath(handle, _stroke);
    canvas.drawLine(const Offset(6, 18), const Offset(9, 15), _stroke);
  }

  void _drawDrill(Canvas canvas) {
    final body = Path()
      ..moveTo(7, 5)
      ..lineTo(18, 5)
      ..quadraticBezierTo(21, 5, 21, 8)
      ..lineTo(21, 11)
      ..lineTo(14, 11)
      ..lineTo(16, 19)
      ..lineTo(10, 19)
      ..lineTo(8, 11)
      ..lineTo(7, 11)
      ..close();
    canvas.drawPath(body, _stroke);
    canvas.drawRect(const Rect.fromLTWH(4, 6, 3, 4), _stroke);
    canvas.drawLine(const Offset(2, 8), const Offset(4, 8), _stroke);
    canvas.drawLine(const Offset(17, 8), const Offset(19, 8), _stroke);
    canvas.drawLine(const Offset(12, 12), const Offset(13, 15), _stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 19, 8, 3),
        const Radius.circular(1),
      ),
      _stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ToolArtworkPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

class FieldOption {
  FieldOption({
    this.id,
    required this.fieldKey,
    required this.label,
    required this.iconKey,
    required this.colorValue,
    this.circleColorValue,
    this.position = 0,
    this.active = true,
  });

  int? id;
  final String fieldKey;
  String label;
  String iconKey;
  int colorValue;
  int? circleColorValue;
  int position;
  bool active;

  IconData get icon => appIconFor(iconKey);
  Color get color =>
      _iconAppearances[iconNameStorageKey(iconKey)]?.line ?? Color(colorValue);
  Color get circleColor =>
      _iconAppearances[iconNameStorageKey(iconKey)]?.circle ??
      (circleColorValue == null
          ? Color(colorValue).withValues(alpha: 0.12)
          : Color(circleColorValue!));

  FieldOption copyWith({
    int? id,
    String? label,
    String? iconKey,
    int? colorValue,
    int? circleColorValue,
    int? position,
    bool? active,
  }) => FieldOption(
    id: id ?? this.id,
    fieldKey: fieldKey,
    label: label ?? this.label,
    iconKey: iconKey ?? this.iconKey,
    colorValue: colorValue ?? this.colorValue,
    circleColorValue: circleColorValue ?? this.circleColorValue,
    position: position ?? this.position,
    active: active ?? this.active,
  );

  Map<String, Object?> toMap({bool includeId = true}) {
    final map = <String, Object?>{
      'field_key': fieldKey,
      'label': label,
      'icon_key': iconKey,
      'color_value': colorValue,
      'circle_color_value': circleColorValue,
      'position': position,
      'active': active ? 1 : 0,
    };
    if (includeId && id != null) map['id'] = id;
    return map;
  }

  factory FieldOption.fromMap(Map<String, Object?> map) => FieldOption(
    id: map['id'] as int?,
    fieldKey: (map['field_key'] as String?) ?? '',
    label: (map['label'] as String?) ?? '',
    iconKey: (map['icon_key'] as String?) ?? 'handyman',
    colorValue: (map['color_value'] as num?)?.toInt() ?? 0xFF546E7A,
    circleColorValue: (map['circle_color_value'] as num?)?.toInt(),
    position: (map['position'] as num?)?.toInt() ?? 0,
    active: ((map['active'] as num?)?.toInt() ?? 1) == 1,
  );
}

List<FieldOption> defaultFieldOptions(String fieldKey) {
  if (fieldKey == 'type') {
    return [
      FieldOption(
        fieldKey: 'type',
        label: 'Herramienta manual',
        iconKey: 'handyman',
        colorValue: 0xFF1976D2,
        position: 0,
      ),
      FieldOption(
        fieldKey: 'type',
        label: 'Herramienta eléctrica',
        iconKey: 'electrical',
        colorValue: 0xFFF9A825,
        position: 1,
      ),
      FieldOption(
        fieldKey: 'type',
        label: 'Repuesto',
        iconKey: 'settings',
        colorValue: 0xFF7E57C2,
        position: 2,
      ),
      FieldOption(
        fieldKey: 'type',
        label: 'Consumible',
        iconKey: 'inventory',
        colorValue: 0xFF00897B,
        position: 3,
      ),
    ];
  }

  return [
    FieldOption(
      fieldKey: 'condition',
      label: 'Bueno',
      iconKey: 'check',
      colorValue: 0xFF43A047,
      position: 0,
    ),
    FieldOption(
      fieldKey: 'condition',
      label: 'Revisar',
      iconKey: 'build',
      colorValue: 0xFFF9A825,
      position: 1,
    ),
    FieldOption(
      fieldKey: 'condition',
      label: 'Averiado',
      iconKey: 'error',
      colorValue: 0xFFE53935,
      position: 2,
    ),
    FieldOption(
      fieldKey: 'condition',
      label: 'Prestado',
      iconKey: 'swap',
      colorValue: 0xFF7E57C2,
      position: 3,
    ),
  ];
}

FieldOption optionForValue(
  List<FieldOption> options,
  String value, {
  required String fieldKey,
}) {
  return options.firstWhere(
    (option) => option.label == value,
    orElse: () => FieldOption(
      fieldKey: fieldKey,
      label: value,
      iconKey: fieldKey == 'type' ? 'category' : 'check',
      colorValue: 0xFF7A7F85,
    ),
  );
}

class ToolTypeStyle {
  const ToolTypeStyle(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

const toolTypeStyles = <ToolTypeStyle>[
  ToolTypeStyle(
    'Herramienta manual',
    Color(0xFF1976D2),
    Icons.handyman_outlined,
  ),
  ToolTypeStyle(
    'Herramienta eléctrica',
    Color(0xFFF59E0B),
    Icons.electrical_services_outlined,
  ),
  ToolTypeStyle('Repuesto', Color(0xFF7E57C2), Icons.settings_outlined),
  ToolTypeStyle('Consumible', Color(0xFF00897B), Icons.inventory_2_outlined),
];

ToolTypeStyle toolTypeStyleFor(String value) {
  return toolTypeStyles.firstWhere(
    (style) => style.label == value,
    orElse: () =>
        const ToolTypeStyle('', Color(0xFF7A7F85), Icons.category_outlined),
  );
}

const toolVoltageOptions = <String>[
  '12 V',
  '18 V',
  '20 V',
  '24 V',
  '36 V',
  '48 V',
  '110 V',
  '230 V',
  '400 V',
];

List<String> voltageOptionsFor(String selected) {
  double numericValue(String value) =>
      double.tryParse(
        RegExp(r'\d+(?:[.,]\d+)?')
                .firstMatch(value)
                ?.group(0)
                ?.replaceAll(',', '.') ??
            '',
      ) ??
      double.infinity;
  final options =
      {...toolVoltageOptions, if (selected.isNotEmpty) selected}.toList()
        ..sort((a, b) {
          final order = numericValue(a).compareTo(numericValue(b));
          return order == 0 ? a.compareTo(b) : order;
        });
  return ['', ...options];
}

class VoltageBadge extends StatelessWidget {
  const VoltageBadge({super.key, required this.voltage});

  final String voltage;

  @override
  Widget build(BuildContext context) {
    final number = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(voltage)?.group(0);
    final color = voltage.isEmpty
        ? const Color(0xFF78909C)
        : const Color(0xFFB77908);
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: voltage.isEmpty
            ? Icon(Icons.remove_rounded, color: color, size: 22)
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      number ?? voltage,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (number != null)
                      Text(
                        'V',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

bool isElectricalToolType(String type) =>
    type.toLowerCase().replaceAll('é', 'e').contains('electric');

class ToolItem {
  ToolItem({
    required this.id,
    required this.name,
    required this.description,
    required this.descriptionDelta,
    required this.barcode,
    required this.quantity,
    required this.unit,
    required this.minimumStock,
    required this.purchasePrice,
    required this.condition,
    this.type = '',
    this.voltage = '',
    List<ToolImage>? images,
  }) : images = images ?? <ToolImage>[];

  final int id;
  String name;
  String description;
  String descriptionDelta;
  String barcode;
  double quantity;
  String unit;
  double minimumStock;
  double purchasePrice;
  String condition;
  String type;
  String voltage;
  List<ToolImage> images;

  String get imagePath {
    if (images.isEmpty) return '';
    final primary = images.where((image) => image.isPrimary);
    return primary.isNotEmpty ? primary.first.path : images.first.path;
  }

  ToolItem copy() => ToolItem(
    id: id,
    name: name,
    description: description,
    descriptionDelta: descriptionDelta,
    barcode: barcode,
    quantity: quantity,
    unit: unit,
    minimumStock: minimumStock,
    purchasePrice: purchasePrice,
    condition: condition,
    type: type,
    voltage: voltage,
    images: images.map((image) => image.copy()).toList(),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'description_delta': descriptionDelta,
    'barcode': barcode,
    'quantity': quantity,
    'unit': unit,
    'minimum_stock': minimumStock,
    'purchase_price': purchasePrice,
    'condition': condition,
    'tool_type': type,
    'voltage': voltage,
    // Se conserva para compatibilidad con versiones antiguas.
    'image_path': imagePath,
  };

  factory ToolItem.fromMap(Map<String, Object?> map) => ToolItem(
    id: map['id'] as int,
    name: (map['name'] as String?) ?? '',
    description: (map['description'] as String?) ?? '',
    descriptionDelta: (map['description_delta'] as String?) ?? '',
    barcode: (map['barcode'] as String?) ?? '',
    quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    unit: (map['unit'] as String?) ?? 'ud',
    minimumStock: (map['minimum_stock'] as num?)?.toDouble() ?? 0,
    purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0,
    condition: (map['condition'] as String?) ?? 'Bueno',
    type: (map['tool_type'] as String?) ?? '',
    voltage: (map['voltage'] as String?) ?? '',
  );
}

class DatabaseStats {
  const DatabaseStats({
    required this.tools,
    required this.images,
    required this.databaseBytes,
    required this.imagesBytes,
  });

  final int tools;
  final int images;
  final int databaseBytes;
  final int imagesBytes;
}

class ToolsDatabase {
  ToolsDatabase._();

  static final ToolsDatabase instance = ToolsDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final base = await getDatabasesPath();
    final path = p.join(base, 'gestor_herramientas.db');

    _database = await openDatabase(
      path,
      version: 7,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tools (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            description_delta TEXT NOT NULL DEFAULT '',
            barcode TEXT NOT NULL DEFAULT '',
            quantity REAL NOT NULL DEFAULT 0,
            unit TEXT NOT NULL DEFAULT 'ud',
            minimum_stock REAL NOT NULL DEFAULT 0,
            purchase_price REAL NOT NULL DEFAULT 0,
            condition TEXT NOT NULL DEFAULT 'Bueno',
            tool_type TEXT NOT NULL DEFAULT '',
            voltage TEXT NOT NULL DEFAULT '',
            image_path TEXT NOT NULL DEFAULT ''
          )
        ''');

        await _createToolImagesTable(db);
        await _createFieldOptionsTable(db);
        await _seedDefaultFieldOptions(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE tools ADD COLUMN image_path TEXT NOT NULL DEFAULT ''",
          );
        }

        if (oldVersion < 3) {
          await _createToolImagesTable(db);
          await db.execute('''
            INSERT INTO tool_images (
              tool_id, path, description, type, position, is_primary, created_at
            )
            SELECT
              id,
              image_path,
              '',
              'General',
              0,
              1,
              datetime('now')
            FROM tools
            WHERE TRIM(COALESCE(image_path, '')) <> ''
          ''');
        }

        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE tools ADD COLUMN tool_type TEXT NOT NULL DEFAULT ''",
          );
        }

        if (oldVersion < 5) {
          await _createFieldOptionsTable(db);
          await _seedDefaultFieldOptions(db);
        }

        if (oldVersion < 6) {
          await db.execute(
            "ALTER TABLE tools ADD COLUMN voltage TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 7) {
          final columns = await db.rawQuery('PRAGMA table_info(field_options)');
          if (!columns.any(
            (column) => column['name'] == 'circle_color_value',
          )) {
            await db.execute(
              'ALTER TABLE field_options ADD COLUMN circle_color_value INTEGER',
            );
          }
        }
      },
    );

    return _database!;
  }

  static Future<void> _createFieldOptionsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        field_key TEXT NOT NULL,
        label TEXT NOT NULL,
        icon_key TEXT NOT NULL DEFAULT 'handyman',
        color_value INTEGER NOT NULL DEFAULT 4283782485,
        circle_color_value INTEGER,
        position INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        UNIQUE(field_key, label)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_field_options_key_position '
      'ON field_options(field_key, position)',
    );
  }

  static Future<void> _seedDefaultFieldOptions(DatabaseExecutor db) async {
    for (final fieldKey in const ['type', 'condition']) {
      for (final option in defaultFieldOptions(fieldKey)) {
        await db.insert(
          'field_options',
          option.toMap(includeId: false),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  static Future<void> _createToolImagesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tool_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tool_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'General',
        position INTEGER NOT NULL DEFAULT 0,
        is_primary INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (tool_id) REFERENCES tools(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tool_images_tool_id '
      'ON tool_images(tool_id)',
    );
  }

  Future<List<ToolItem>> loadTools() async {
    final db = await database;
    final rows = await db.query('tools', orderBy: 'id DESC');
    final tools = rows.map(ToolItem.fromMap).toList();

    if (tools.isEmpty) return tools;

    final imageRows = await db.query(
      'tool_images',
      orderBy: 'tool_id ASC, is_primary DESC, position ASC, id ASC',
    );

    final byTool = <int, List<ToolImage>>{};
    for (final row in imageRows) {
      final image = ToolImage.fromMap(row);
      byTool.putIfAbsent(image.toolId, () => <ToolImage>[]).add(image);
    }

    for (final tool in tools) {
      tool.images = byTool[tool.id] ?? <ToolImage>[];

      // Protección extra para bases antiguas que no hubieran migrado la foto.
      if (tool.images.isEmpty) {
        final legacyPath =
            (rows.firstWhere((row) => row['id'] == tool.id)['image_path']
                as String?) ??
            '';
        if (legacyPath.trim().isNotEmpty) {
          tool.images = [
            ToolImage(
              toolId: tool.id,
              path: legacyPath,
              position: 0,
              isPrimary: true,
            ),
          ];
        }
      }
    }

    return tools;
  }

  Future<List<ToolImage>> loadImages(int toolId) async {
    final db = await database;
    final rows = await db.query(
      'tool_images',
      where: 'tool_id = ?',
      whereArgs: [toolId],
      orderBy: 'is_primary DESC, position ASC, id ASC',
    );
    return rows.map(ToolImage.fromMap).toList();
  }

  Future<void> saveTool(ToolItem item) async {
    final db = await database;

    final oldRows = await db.query(
      'tool_images',
      columns: ['path'],
      where: 'tool_id = ?',
      whereArgs: [item.id],
    );
    final oldPaths = oldRows
        .map((row) => (row['path'] as String?) ?? '')
        .where((path) => path.isNotEmpty)
        .toSet();

    _normalizeImages(item);

    await db.transaction((txn) async {
      await txn.insert(
        'tools',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'tool_images',
        where: 'tool_id = ?',
        whereArgs: [item.id],
      );

      for (final image in item.images) {
        image.toolId = item.id;
        await txn.insert('tool_images', image.toMap(includeId: false));
      }
    });

    final newPaths = item.images.map((image) => image.path).toSet();
    final stalePaths = oldPaths.difference(newPaths);

    for (final path in stalePaths) {
      final count =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM tool_images WHERE path = ?',
              [path],
            ),
          ) ??
          0;
      if (count == 0) {
        final file = File(path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
  }

  void _normalizeImages(ToolItem item) {
    for (var index = 0; index < item.images.length; index++) {
      final image = item.images[index];
      image.toolId = item.id;
      image.position = index;
    }

    if (item.images.isEmpty) return;

    var primaryIndex = item.images.indexWhere((image) => image.isPrimary);
    if (primaryIndex < 0) primaryIndex = 0;

    for (var index = 0; index < item.images.length; index++) {
      item.images[index].isPrimary = index == primaryIndex;
    }
  }

  Future<List<FieldOption>> loadFieldOptions(
    String fieldKey, {
    bool includeInactive = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      'field_options',
      where: includeInactive ? 'field_key = ?' : 'field_key = ? AND active = 1',
      whereArgs: [fieldKey],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map(FieldOption.fromMap).toList();
  }

  Future<FieldOption> saveFieldOption(
    FieldOption option, {
    String? previousLabel,
  }) async {
    final db = await database;

    return db.transaction((txn) async {
      var position = option.position;
      if (option.id == null) {
        final result = await txn.rawQuery(
          'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
          'FROM field_options WHERE field_key = ?',
          [option.fieldKey],
        );
        position = (result.first['next_position'] as num?)?.toInt() ?? position;
      }

      final stored = option.copyWith(position: position);

      int id;
      if (option.id == null) {
        id = await txn.insert('field_options', stored.toMap(includeId: false));
      } else {
        id = option.id!;
        await txn.update(
          'field_options',
          stored.toMap(includeId: false),
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      final oldLabel = previousLabel?.trim() ?? '';
      final newLabel = stored.label.trim();
      if (oldLabel.isNotEmpty && oldLabel != newLabel) {
        final column = stored.fieldKey == 'type' ? 'tool_type' : 'condition';
        await txn.update(
          'tools',
          {column: newLabel},
          where: '$column = ?',
          whereArgs: [oldLabel],
        );
      }

      return stored.copyWith(id: id);
    });
  }

  Future<int> countFieldOptionUsage(FieldOption option) async {
    final db = await database;
    final column = option.fieldKey == 'type' ? 'tool_type' : 'condition';
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tools WHERE $column = ?', [
            option.label,
          ]),
        ) ??
        0;
  }

  Future<void> deleteFieldOption(
    FieldOption option, {
    String? replacementLabel,
  }) async {
    if (option.id == null) return;
    final db = await database;

    await db.transaction((txn) async {
      final column = option.fieldKey == 'type' ? 'tool_type' : 'condition';
      final count =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM tools WHERE $column = ?', [
              option.label,
            ]),
          ) ??
          0;

      if (count > 0) {
        final replacement = replacementLabel?.trim() ?? '';
        if (replacement.isEmpty) {
          throw StateError(
            'La opción está en uso por $count herramientas y necesita un reemplazo.',
          );
        }
        await txn.update(
          'tools',
          {column: replacement},
          where: '$column = ?',
          whereArgs: [option.label],
        );
      }

      await txn.delete(
        'field_options',
        where: 'id = ?',
        whereArgs: [option.id],
      );
    });
  }

  Future<void> seedIfEmpty(List<ToolItem> defaults) async {
    final db = await database;
    final countResult = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tools'),
    );
    if ((countResult ?? 0) != 0) return;

    final batch = db.batch();
    for (final item in defaults) {
      batch.insert('tools', item.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<DatabaseStats> getStats() async {
    final db = await database;

    final toolsCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tools'),
        ) ??
        0;
    final imagesCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tool_images'),
        ) ??
        0;

    final path = await databasePath;
    final dbFile = File(path);
    final databaseBytes = await dbFile.exists() ? await dbFile.length() : 0;

    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'tool_images'));
    final imagesBytes = await _directorySize(imagesDir);

    return DatabaseStats(
      tools: toolsCount,
      images: imagesCount,
      databaseBytes: databaseBytes,
      imagesBytes: imagesBytes,
    );
  }

  Future<String> integrityCheck() async {
    final db = await database;
    final rows = await db.rawQuery('PRAGMA integrity_check');
    if (rows.isEmpty) return 'Sin resultado';

    final value = rows.first.values.isEmpty ? null : rows.first.values.first;
    return value?.toString() ?? 'Sin resultado';
  }

  Future<List<Map<String, Object?>>> databaseOverview() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        t.id,
        t.name,
        t.barcode,
        t.tool_type,
        t.voltage,
        COUNT(i.id) AS image_count
      FROM tools t
      LEFT JOIN tool_images i ON i.tool_id = t.id
      GROUP BY t.id, t.name, t.barcode, t.tool_type, t.voltage
      ORDER BY t.id DESC
    ''');
  }

  Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;

    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<String> get databasePath async {
    final base = await getDatabasesPath();
    return p.join(base, 'gestor_herramientas.db');
  }

  Future<void> closeForBackup() async {
    final db = _database;
    if (db != null) {
      try {
        await db.execute('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      await db.close();
      _database = null;
    }
  }

  Future<void> reopen() async {
    await database;
  }
}

class BackupManager {
  BackupManager._();

  static const int formatVersion = 1;

  static Future<Directory> _imagesDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'tool_images'));
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static Future<File> createBackup() async {
    final temp = await getTemporaryDirectory();
    final stamp = _stamp();
    final workDir = Directory(p.join(temp.path, 'gh_backup_work_$stamp'));
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);

    final databasePath = await ToolsDatabase.instance.databasePath;
    final imagesDir = await _imagesDirectory();

    await ToolsDatabase.instance.closeForBackup();

    try {
      final dbFile = File(databasePath);
      if (!await dbFile.exists()) {
        throw StateError('No se ha encontrado la base de datos');
      }

      final databaseDir = Directory(p.join(workDir.path, 'database'));
      await databaseDir.create(recursive: true);
      await dbFile.copy(p.join(databaseDir.path, 'gestor_herramientas.db'));

      final backupImagesDir = Directory(p.join(workDir.path, 'tool_images'));
      if (await imagesDir.exists()) {
        await _copyDirectory(imagesDir, backupImagesDir);
      } else {
        await backupImagesDir.create(recursive: true);
      }

      final manifest = <String, Object?>{
        'format': 'gestor_herramientas_backup',
        'format_version': formatVersion,
        'created_at': DateTime.now().toIso8601String(),
        'database': 'database/gestor_herramientas.db',
        'images': 'tool_images',
        'note': 'Copia completa de SQLite e imágenes. Incluye automáticamente campos futuros guardados en la base de datos.',
      };
      await File(p.join(workDir.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );

      final archive = Archive();
      await _addDirectoryToArchive(archive, workDir, workDir.path);

      final zipBytes = ZipEncoder().encode(archive);

      final output = File(
        p.join(temp.path, 'gestor_herramientas_backup_$stamp.zip'),
      );
      await output.writeAsBytes(zipBytes, flush: true);
      return output;
    } finally {
      await ToolsDatabase.instance.reopen();
      if (await workDir.exists()) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<void> restoreBackup(String zipPath) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw StateError('No se encuentra el archivo de copia');
    }

    final temp = await getTemporaryDirectory();
    final stamp = _stamp();
    final restoreDir = Directory(p.join(temp.path, 'gh_restore_$stamp'));
    if (await restoreDir.exists()) {
      await restoreDir.delete(recursive: true);
    }
    await restoreDir.create(recursive: true);

    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);

      for (final entry in archive) {
        final normalized = p.normalize(entry.name);
        if (p.isAbsolute(normalized) ||
            normalized == '..' ||
            normalized.startsWith('../') ||
            normalized.contains('/../')) {
          throw const FormatException('La copia contiene una ruta no válida');
        }

        final targetPath = p.join(restoreDir.path, normalized);
        if (entry.isFile) {
          final output = File(targetPath);
          await output.parent.create(recursive: true);
          await output.writeAsBytes(entry.content as List<int>, flush: true);
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }

      final manifestFile = File(p.join(restoreDir.path, 'manifest.json'));
      final restoredDb = File(
        p.join(restoreDir.path, 'database', 'gestor_herramientas.db'),
      );

      if (!await manifestFile.exists() || !await restoredDb.exists()) {
        throw const FormatException(
          'El archivo no es una copia válida del Gestor de Herramientas',
        );
      }

      final manifestRaw = jsonDecode(await manifestFile.readAsString());
      if (manifestRaw is! Map ||
          manifestRaw['format'] != 'gestor_herramientas_backup') {
        throw const FormatException('Formato de copia no reconocido');
      }

      final version = (manifestRaw['format_version'] as num?)?.toInt() ?? 0;
      if (version > formatVersion) {
        throw const FormatException(
          'La copia fue creada por una versión más nueva de la aplicación',
        );
      }

      final dbDestination = await ToolsDatabase.instance.databasePath;
      final imagesDestination = await _imagesDirectory();
      final restoredImages = Directory(p.join(restoreDir.path, 'tool_images'));

      await ToolsDatabase.instance.closeForBackup();

      try {
        final destinationDbFile = File(dbDestination);
        await destinationDbFile.parent.create(recursive: true);
        await restoredDb.copy(dbDestination);

        if (await imagesDestination.exists()) {
          await imagesDestination.delete(recursive: true);
        }

        if (await restoredImages.exists()) {
          await _copyDirectory(restoredImages, imagesDestination);
        } else {
          await imagesDestination.create(recursive: true);
        }
      } finally {
        await ToolsDatabase.instance.reopen();
      }
    } finally {
      if (await restoreDir.exists()) {
        try {
          await restoreDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);

    await for (final entity in source.list(recursive: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(destination.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, name));
      }
    }
  }

  static Future<void> _addDirectoryToArchive(
    Archive archive,
    Directory directory,
    String rootPath,
  ) async {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;

      final relative = p.relative(entity.path, from: rootPath);
      final archiveName = relative.replaceAll('\\', '/');
      final data = await entity.readAsBytes();
      archive.addFile(ArchiveFile(archiveName, data.length, data));
    }
  }
}

class ConditionStyle {
  const ConditionStyle(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

const conditionStyles = <ConditionStyle>[
  ConditionStyle('Bueno', Color(0xFF43A047), Icons.check_circle_outline),
  ConditionStyle('Revisar', Color(0xFFF9A825), Icons.build_circle_outlined),
  ConditionStyle('Averiado', Color(0xFFE53935), Icons.error_outline),
  ConditionStyle('Prestado', Color(0xFF7E57C2), Icons.swap_horiz),
];

ConditionStyle conditionStyleFor(String value) {
  return conditionStyles.firstWhere(
    (style) => style.label == value,
    orElse: () => conditionStyles.first,
  );
}

class StartupStatusPage extends StatelessWidget {
  const StartupStatusPage({
    super.key,
    this.hasError = false,
    this.onRetry,
    this.errorDetails,
  });

  final bool hasError;
  final VoidCallback? onRetry;
  final String? errorDetails;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasError)
                  const Icon(
                    Icons.error_outline,
                    size: 42,
                    color: Color(0xFF72777D),
                  )
                else
                  const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF168BD2),
                      semanticsLabel: 'Cargando la aplicación',
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Gestor de herramientas',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  hasError
                      ? 'No se pudieron cargar las herramientas.'
                      : 'Cargando…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF72777D)),
                ),
                if (hasError) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  ),
                  if (errorDetails != null)
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: errorDetails!));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Error copiado')),
                        );
                      },
                      child: const Text('Copiar error'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ToolsHomePage extends StatefulWidget {
  const ToolsHomePage({super.key});

  @override
  State<ToolsHomePage> createState() => _ToolsHomePageState();
}

class _ToolsHomePageState extends State<ToolsHomePage> {
  final _searchController = TextEditingController();

  final List<ToolItem> _defaultItems = [
    ToolItem(
      id: 1,
      name: 'Destornillador aislado',
      description: 'Destornillador VDE para trabajos eléctricos.',
      descriptionDelta: '',
      barcode: '841000000001',
      quantity: 4,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 8.50,
      condition: 'Bueno',
    ),
    ToolItem(
      id: 2,
      name: 'Multímetro',
      description: 'Multímetro digital de uso general.',
      descriptionDelta: '',
      barcode: '841000000002',
      quantity: 2,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 64.90,
      condition: 'Revisar',
    ),
    ToolItem(
      id: 3,
      name: 'Taladro',
      description: 'Taladro con cable para taller.',
      descriptionDelta: '',
      barcode: '841000000003',
      quantity: 1,
      unit: 'ud',
      minimumStock: 1,
      purchasePrice: 89.00,
      condition: 'Bueno',
    ),
  ];

  final List<ToolItem> _items = [];
  List<FieldOption> _conditionOptions = defaultFieldOptions('condition');
  bool _loading = true;
  bool _loadError = false;
  String? _loadErrorDetails;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
      _loadError = false;
      _loadErrorDetails = null;
    });
    var loadStage = 'Abrir los datos guardados';
    try {
      await ToolsDatabase.instance.seedIfEmpty(_defaultItems);
      loadStage = 'Leer las herramientas';
      final items = await ToolsDatabase.instance.loadTools();
      loadStage = 'Leer los iconos';
      await loadIconNames();
      await loadIconSettings();
      loadStage = 'Leer los estados';
      final conditionOptions = await ToolsDatabase.instance.loadFieldOptions(
        'condition',
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _conditionOptions = conditionOptions.isEmpty
            ? defaultFieldOptions('condition')
            : conditionOptions;
        _loading = false;
      });
    } catch (error) {
      debugPrint('No se pudieron cargar las herramientas: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
        _loadErrorDetails = '$loadStage\n$error';
      });
    }
  }

  String get _query => _searchController.text.trim().toLowerCase();

  List<ToolItem> get _visibleItems {
    if (_query.isEmpty) return _items;
    return _items
        .where(
          (item) =>
              item.name.toLowerCase().contains(_query) ||
              item.description.toLowerCase().contains(_query) ||
              item.barcode.toLowerCase().contains(_query) ||
              item.type.toLowerCase().contains(_query),
        )
        .toList();
  }

  Future<void> _openEditor({ToolItem? item}) async {
    final result = await Navigator.of(context).push<ToolItem>(
      MaterialPageRoute(
        builder: (_) => EditToolPage(
          item: item?.copy(),
          nextId: _items.isEmpty
              ? 1
              : _items.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1,
        ),
      ),
    );

    if (result == null) return;

    await ToolsDatabase.instance.saveTool(result);

    if (!mounted) return;
    setState(() {
      final index = _items.indexWhere((element) => element.id == result.id);
      if (index >= 0) {
        _items[index] = result;
      } else {
        _items.insert(0, result);
      }
    });
  }

  Future<void> _openIconManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const IconManagementPage()),
    );
    if (mounted) await _loadItems();
  }

  Future<void> _openFieldOptionsManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FieldOptionsManagementPage()),
    );
    await _loadItems();
  }

  Future<void> _createBackup() async {
    try {
      final backup = await BackupManager.createBackup();
      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(backup.path)],
        subject: 'Copia de seguridad · Gestor de Herramientas',
        text: 'Copia completa de la base de datos y las imágenes del Gestor de Herramientas.',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la copia: $error')),
      );
    }
  }

  Future<bool> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
    );

    final path = picked?.files.single.path;
    if (path == null || !mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restore),
        title: const Text('Restaurar copia'),
        content: const Text(
          'Se sustituirán la base de datos y las imágenes actuales por las '
          'contenidas en la copia. Esta operación no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await BackupManager.restoreBackup(path);
      await _loadItems();
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copia restaurada correctamente')),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo restaurar la copia: $error')),
      );
      return false;
    }
  }

  Future<void> _openDatabaseManager() async {
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DatabaseManagementPage(
          onCreateBackup: _createBackup,
          onRestoreBackup: _restoreBackup,
        ),
      ),
    );

    if (restored == true) {
      await _loadItems();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadError) {
      return StartupStatusPage(
        hasError: _loadError,
        onRetry: _loadItems,
        errorDetails: _loadErrorDetails,
      );
    }
    final visible = _visibleItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis herramientas · QUILL V22',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Gestor de iconos',
            icon: const Icon(Icons.image_outlined),
            onPressed: _openIconManager,
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'icons':
                  _openIconManager();
                case 'database':
                  _openDatabaseManager();
                case 'fields':
                  _openFieldOptionsManager();
                case 'backup':
                  _createBackup();
                case 'restore':
                  _restoreBackup();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'icons',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.image_outlined),
                  title: Text('Gestor de iconos'),
                ),
              ),
              PopupMenuItem(
                value: 'database',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storage_outlined),
                  title: Text('Gestión de base de datos'),
                ),
              ),
              PopupMenuItem(
                value: 'fields',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune_outlined),
                  title: Text('Configurar Tipo y Estado'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Crear copia de seguridad'),
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restore),
                  title: Text('Restaurar copia'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: const Color(0xFF168BD2),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 30),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar herramientas',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(
                children: [
                  Text(
                    '${visible.length} artículos',
                    style: const TextStyle(
                      color: Color(0xFF72777D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.tune, size: 20),
                    label: const Text('Filtrar'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text(
                        'No se encontraron herramientas',
                        style: TextStyle(color: Color(0xFF7A7F85)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 92),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final style = optionForValue(
                          _conditionOptions,
                          item.condition,
                          fieldKey: 'condition',
                        );

                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _openEditor(item: item),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF4FE),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child:
                                        item.imagePath.isNotEmpty &&
                                            File(item.imagePath).existsSync()
                                        ? Image.file(
                                            File(item.imagePath),
                                            fit: BoxFit.cover,
                                          )
                                        : const Icon(
                                            Icons.handyman_outlined,
                                            color: Color(0xFF168BD2),
                                            size: 28,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF25292D),
                                          ),
                                        ),
                                        if (item.voltage.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            item.voltage,
                                            style: const TextStyle(
                                              color: Color(0xFF6F747A),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 9,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: style.color.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  fieldOptionIconWidget(
                                                    style,
                                                    size: 15,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    style.label,
                                                    style: TextStyle(
                                                      color: style.color,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              'Cantidad: ${formatNumber(item.quantity)} ${item.unit}',
                                              style: const TextStyle(
                                                color: Color(0xFF6F747A),
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF9AA0A6),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Directory> customIconsDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(docs.path, 'tool_images', 'custom_icons'));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Set<String> _hiddenIconKeys = {};
Set<String> _removedIconKeys = {};
List<String> _recentIconIds = [];
Set<String> _favoriteIconKeys = {};
List<String> _customIconCategories = [];
Map<String, String> _iconGroupOverrides = {};

List<String> get iconGroups => [
  ...appIconCategories.where((g) => g != 'Todos'),
  ..._customIconCategories,
];
List<String> get iconFilters => ['Todos', 'Favoritos', ...iconGroups];
bool isIconFavorite(String key) =>
    _favoriteIconKeys.contains(iconNameStorageKey(key));
bool isIconHidden(String key) =>
    _hiddenIconKeys.contains(iconNameStorageKey(key)) || isIconRemoved(key);
bool isIconRemoved(String key) =>
    _removedIconKeys.contains(iconNameStorageKey(key));
String iconCategoryForKey(
  String key, [
  Map<String, String> customGroups = const {},
]) =>
    _iconGroupOverrides[iconNameStorageKey(key)] ??
    (isCustomIconKey(key)
        ? customGroups[key] ?? 'Mis iconos'
        : appIconChoiceFor(key).category);

Future<File> iconSettingsFile() async {
  final docs = await getApplicationDocumentsDirectory();
  return File(p.join(docs.path, 'tool_images', 'icon_settings.json'));
}

Future<void> loadIconSettings() async {
  final hidden = <String>{};
  final removed = <String>{};
  final recent = <String>[];
  final favorites = <String>{};
  final custom = <String>[];
  final groups = <String, String>{};
  final appearances = <String, IconAppearance>{};
  try {
    final file = await iconSettingsFile();
    if (await file.exists()) {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map) {
        if (raw['appearances'] is Map) {
          for (final entry in (raw['appearances'] as Map).entries) {
            final value = entry.value;
            if (entry.key is String && value is Map &&
                value['line'] is int && value['circle'] is int) {
              appearances[entry.key as String] =
                  IconAppearance(value['line'] as int, value['circle'] as int);
            }
          }
        }
        if (raw['recent'] is List) {
          for (final id in (raw['recent'] as List).whereType<String>()) {
            if (!recent.contains(id) && recent.length < 30) recent.add(id);
          }
        }
        if (raw['removed'] is List)
          removed.addAll((raw['removed'] as List).whereType<String>());
        if (raw['hidden'] is List)
          hidden.addAll((raw['hidden'] as List).whereType<String>());
        if (raw['favorites'] is List)
          favorites.addAll((raw['favorites'] as List).whereType<String>());
        if (raw['customGroups'] is List) {
          for (final name
              in (raw['customGroups'] as List).whereType<String>()) {
            final clean = name.trim();
            if (clean.isNotEmpty &&
                clean.length <= 40 &&
                ![
                  ...appIconCategories,
                  'Favoritos',
                  ...custom,
                ].any((g) => g.toLowerCase() == clean.toLowerCase()))
              custom.add(clean);
          }
        }
        if (raw['groups'] is Map) {
          for (final entry in (raw['groups'] as Map).entries) {
            if (entry.key is String &&
                entry.value is String &&
                [
                  ...appIconCategories.where((g) => g != 'Todos'),
                  ...custom,
                ].contains(entry.value)) {
              groups[entry.key as String] = entry.value as String;
            }
          }
        }
      }
    }
  } catch (_) {}
  _hiddenIconKeys = hidden;
  _removedIconKeys = removed;
  _recentIconIds = recent;
  _favoriteIconKeys = favorites;
  _customIconCategories = custom;
  _iconGroupOverrides = groups;
  _iconAppearances = appearances;
}

Future<void> _persistIconSettings({
  required Set<String> hidden,
  required Set<String> favorites,
  required List<String> customGroups,
  required Map<String, String> groups,
  Map<String, IconAppearance>? appearances,
  Set<String>? removed,
  List<String>? recent,
}) async {
  final file = await iconSettingsFile();
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(
    jsonEncode({
      'hidden': hidden.toList(),
      'removed': (removed ?? _removedIconKeys).toList(),
      'recent': recent ?? _recentIconIds,
      'favorites': favorites.toList(),
      'customGroups': customGroups,
      'groups': groups,
      'appearances': (appearances ?? _iconAppearances).map(
        (key, value) => MapEntry(key, {
          'line': value.lineValue, 'circle': value.circleValue,
        }),
      ),
    }),
    flush: true,
  );
  await temporary.rename(file.path);
  _hiddenIconKeys = hidden;
  _favoriteIconKeys = favorites;
  _customIconCategories = customGroups;
  _iconGroupOverrides = groups;
  if (appearances != null) _iconAppearances = appearances;
  if (removed != null) _removedIconKeys = removed;
  if (recent != null) _recentIconIds = recent;
}



List<String> recentIconKeys(Iterable<String> available, {bool includeHidden = false}) {
  final byId = {
    for (final key in available)
      if (!isIconRemoved(key) && (includeHidden || !isIconHidden(key)))
        iconNameStorageKey(key): key,
  };
  return [for (final id in _recentIconIds) if (byId.containsKey(id)) byId[id]!];
}

Future<void> recordRecentIcon(String key) async {
  if (isIconHidden(key)) return;
  final id = iconNameStorageKey(key);
  final recent = [id, ..._recentIconIds.where((saved) => saved != id)].take(30).toList();
  await _persistIconSettings(
    hidden: Set<String>.from(_hiddenIconKeys),
    favorites: Set<String>.from(_favoriteIconKeys),
    customGroups: List<String>.from(_customIconCategories),
    groups: Map<String, String>.from(_iconGroupOverrides),
    recent: recent,
  );
}

class _IconDetailCard extends StatelessWidget {
  const _IconDetailCard({
    required this.iconKey, required this.group, required this.position,
    required this.total, required this.onPrevious, required this.onNext,
    this.onColors, this.onFavorite, this.onManage, this.onSelect, this.onRestore,
  });
  final String iconKey, group;
  final int position, total;
  final VoidCallback? onPrevious, onNext, onColors, onFavorite, onManage, onSelect, onRestore;
  String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  Widget _color(String label, Color color) => Chip(
    avatar: Container(width: 18, height: 18,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF999999)))),
    label: Text('$label: ${_hex(color)}'),
  );
  @override
  Widget build(BuildContext context) {
    final appearance = iconAppearance(iconKey);
    return ListView(
      key: const ValueKey('icon_detail'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: 'Icono anterior', onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left)),
          Flexible(child: Text('${position + 1} de $total', textAlign: TextAlign.center)),
          IconButton(tooltip: 'Icono siguiente', onPressed: onNext,
            icon: const Icon(Icons.chevron_right)),
        ]),
        Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(width: 112, height: 112, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: appearance.circle, shape: BoxShape.circle),
              child: iconWidgetForKey(iconKey, color: appearance.line, size: 70)),
            const SizedBox(height: 16),
            Text(appIconLabel(iconKey), key: const ValueKey('icon_detail_name'),
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Grupo: $group', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
              _color('Fondo', appearance.circle),
              _color('Trazo', appearance.line),
            ]),
            const SizedBox(height: 8),
            Text(isIconFavorite(iconKey) ? 'Favorito' : 'Sin marcar como favorito'),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              if (onColors != null) OutlinedButton.icon(
                onPressed: onColors, icon: const Icon(Icons.palette_outlined),
                label: const Text('Cambiar colores')),
              if (onFavorite != null) OutlinedButton.icon(
                onPressed: onFavorite, icon: Icon(isIconFavorite(iconKey) ? Icons.star : Icons.star_border),
                label: Text(isIconFavorite(iconKey) ? 'Quitar de favoritos' : 'Añadir a favoritos')),
              if (onManage != null) OutlinedButton.icon(
                onPressed: onManage, icon: const Icon(Icons.edit_outlined),
                label: const Text('Más opciones')),
              if (onRestore != null) FilledButton(
                onPressed: onRestore, child: const Text('Restaurar')),
              if (onSelect != null) FilledButton(
                onPressed: onSelect, child: const Text('Elegir este icono')),
            ]),
          ]),
        )),
      ],
    );
  }
}

class _IconQuickView extends StatelessWidget {
  const _IconQuickView({required this.keys, required this.tileBuilder,
    required this.gridDelegate, this.includeHidden = false});
  final List<String> keys;
  final Widget Function(String) tileBuilder;
  final SliverGridDelegate gridDelegate;
  final bool includeHidden;
  @override
  Widget build(BuildContext context) {
    final favorites = keys.where(isIconFavorite).toList();
    final recent = recentIconKeys(keys, includeHidden: includeHidden);
    return CustomScrollView(key: const ValueKey('icon_quick_view'), slivers: [
      for (final section in {'Favoritos': favorites, 'Recientes': recent}.entries) ...[
        SliverToBoxAdapter(child: _iconColorHeading(section.key, section.value.length,
          ValueKey('icon_quick_${section.key}'))),
        if (section.value.isEmpty)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16),
            child: Text(section.key == 'Favoritos'
                ? 'Marca iconos como favoritos para tenerlos aquí.'
                : 'Aquí aparecerán los últimos iconos que selecciones.')))
        else
          SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) => tileBuilder(section.value[index]),
                childCount: section.value.length))),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]);
  }
}

class IconTrashResult {
  const IconTrashResult(this.emptied, this.keptForUsage);
  final int emptied;
  final int keptForUsage;
}

Future<IconTrashResult> emptyIconTrash({Set<String>? protectedKeys}) async {
  // Read assignments before moving any file. If the database cannot be read,
  // abort rather than treating all icons as unused.
  if (protectedKeys == null) {
    final db = await ToolsDatabase.instance.database;
    final rows = await db.query('field_options', columns: ['icon_key']);
    protectedKeys = rows.map((row) => row['icon_key']).whereType<String>().toSet();
  }
  final protectedIds = protectedKeys.map(iconNameStorageKey).toSet();
  final keys = await loadCustomIconKeys();
  final trash = Set<String>.from(_hiddenIconKeys)..removeAll(_removedIconKeys);
  if (trash.isEmpty) return const IconTrashResult(0, 0);
  final directory = await customIconsDirectory();
  final staged = Directory(p.join(directory.path,
      'purge_pending_${DateTime.now().microsecondsSinceEpoch}'));
  final moved = <String, String>{};
  try {
    for (final key in keys) {
      final id = iconNameStorageKey(key);
      if (!trash.contains(id) || protectedIds.contains(id)) continue;
      final path = customIconPathFromKey(key);
      for (final candidate in [path, '$path.group.json']) {
        final file = File(candidate);
        if (!await file.exists()) continue;
        await staged.create(recursive: true);
        final target = p.join(staged.path, p.basename(candidate));
        await file.rename(target);
        moved[candidate] = target;
      }
    }
    await _persistIconSettings(
      hidden: Set<String>.from(_hiddenIconKeys)..removeAll(trash),
      favorites: Set<String>.from(_favoriteIconKeys)..removeAll(trash),
      customGroups: List<String>.from(_customIconCategories),
      groups: Map<String, String>.from(_iconGroupOverrides),
      removed: Set<String>.from(_removedIconKeys)..addAll(trash),
      recent: _recentIconIds.where((id) => !trash.contains(id)).toList(),
    );
  } catch (_) {
    for (final entry in moved.entries) {
      final file = File(entry.value);
      if (await file.exists()) await file.rename(entry.key);
    }
    if (await staged.exists()) await staged.delete(recursive: true);
    rethrow;
  }
  // Staged files have no remaining assignments. A cleanup failure does not
  // make them visible again or affect the original files kept for usage.
  try {
    if (await staged.exists()) await staged.delete(recursive: true);
  } catch (_) {}
  return IconTrashResult(trash.length, trash.intersection(protectedIds).length);
}

Future<void> updateIconSettings(
  String key, {
  bool? hidden,
  bool? favorite,
  String? group,
}) async {
  final hiddenKeys = Set<String>.from(_hiddenIconKeys);
  final favorites = Set<String>.from(_favoriteIconKeys);
  final groups = Map<String, String>.from(_iconGroupOverrides);
  final id = iconNameStorageKey(key);
  if (hidden == true) hiddenKeys.add(id);
  if (hidden == false) hiddenKeys.remove(id);
  if (favorite == true) favorites.add(id);
  if (favorite == false) favorites.remove(id);
  if (group != null) {
    if (!iconGroups.contains(group))
      throw ArgumentError('Grupo de iconos no válido');
    groups[id] = group;
  }
  await _persistIconSettings(
    hidden: hiddenKeys,
    favorites: favorites,
    customGroups: List<String>.from(_customIconCategories),
    groups: groups,
  );
}

String? iconGroupNameError(String name, {String? original}) {
  final clean = name.trim();
  if (clean.isEmpty) return 'Escribe un nombre';
  if (clean.length > 40) return 'Usa un máximo de 40 caracteres';
  if ([
    ...appIconCategories,
    'Favoritos',
    ..._customIconCategories,
  ].any((g) => g != original && g.toLowerCase() == clean.toLowerCase()))
    return 'Ya existe un grupo con ese nombre';
  return null;
}

Future<void> saveIconGroup(String name, {String? original}) async {
  final error = iconGroupNameError(name, original: original);
  if (error != null) throw ArgumentError(error);
  if (original != null && !_customIconCategories.contains(original))
    throw ArgumentError('Grupo no editable');
  final clean = name.trim();
  final custom = List<String>.from(_customIconCategories);
  final groups = Map<String, String>.from(_iconGroupOverrides);
  if (original == null) {
    custom.add(clean);
  } else {
    custom[custom.indexOf(original)] = clean;
    groups.updateAll((key, group) => group == original ? clean : group);
  }
  await _persistIconSettings(
    hidden: Set<String>.from(_hiddenIconKeys),
    favorites: Set<String>.from(_favoriteIconKeys),
    customGroups: custom,
    groups: groups,
  );
}

Future<void> deleteIconGroup(String name) async {
  if (!_customIconCategories.contains(name))
    throw ArgumentError('Grupo no editable');
  final groups = Map<String, String>.from(_iconGroupOverrides);
  groups.updateAll((key, group) => group == name ? 'Mis iconos' : group);
  await _persistIconSettings(
    hidden: Set<String>.from(_hiddenIconKeys),
    favorites: Set<String>.from(_favoriteIconKeys),
    customGroups: _customIconCategories.where((g) => g != name).toList(),
    groups: groups,
  );
}

Future<bool> showIconRename(BuildContext context, String key) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _IconRenameDialog(iconKey: key),
  );
  if (name == null) return false;
  await saveIconName(key, name);
  return true;
}

Future<File> iconNamesFile() async {
  final docs = await getApplicationDocumentsDirectory();
  return File(p.join(docs.path, 'tool_images', 'icon_names.json'));
}

Future<void> loadIconNames() async {
  final names = <String, String>{};
  try {
    final file = await iconNamesFile();
    if (await file.exists()) {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.key is String &&
              entry.value is String &&
              (entry.value as String).trim().isNotEmpty) {
            names[entry.key as String] = (entry.value as String).trim();
          }
        }
      }
    }
  } catch (_) {
    // Un fichero ausente o inválido conserva los nombres de fábrica.
  }
  _iconNameOverrides = names;
}

Future<void> saveIconName(String key, String name) async {
  final updated = Map<String, String>.from(_iconNameOverrides);
  final value = name.trim();
  if (value.isEmpty || value == defaultAppIconLabel(key)) {
    updated.remove(iconNameStorageKey(key));
  } else {
    updated[iconNameStorageKey(key)] = value;
  }
  final file = await iconNamesFile();
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(jsonEncode(updated), flush: true);
  await temporary.rename(file.path);
  _iconNameOverrides = updated;
}

Future<List<String>> loadCustomIconKeys() async {
  await loadIconNames();
  await loadIconSettings();
  final directory = await customIconsDirectory();
  final supported = <String>{'.png', '.jpg', '.jpeg', '.webp', '.svg'};
  final keys = <String>[];

  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    if (!supported.contains(p.extension(entity.path).toLowerCase())) {
      continue;
    }
    keys.add('custom:${entity.path}');
  }

  keys.sort(
    (a, b) =>
        appIconLabel(a).toLowerCase().compareTo(appIconLabel(b).toLowerCase()),
  );
  return keys;
}

Future<Map<String, String>> loadCustomIconGroups(List<String> keys) async {
  final groups = <String, String>{};
  for (final key in keys) {
    var group = 'Mis iconos';
    try {
      final file = File('${customIconPathFromKey(key)}.group.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        final saved = data is Map ? data['group'] : null;
        if (saved is String && saved != 'Todos' && iconGroups.contains(saved)) {
          group = saved;
        }
      }
    } catch (_) {
      // Los iconos anteriores o sin metadatos siguen en Mis iconos.
    }
    groups[key] = _iconGroupOverrides[iconNameStorageKey(key)] ?? group;
  }
  return groups;
}

Future<void> saveCustomIconGroup(String key, String group) async {
  if (!isCustomIconKey(key) ||
      group == 'Todos' ||
      !iconGroups.contains(group)) {
    throw ArgumentError('Grupo de iconos no válido');
  }
  await updateIconSettings(key, group: group);
  await File('${customIconPathFromKey(key)}.group.json')
      .writeAsString(jsonEncode({'group': group}), flush: true);
}

Future<List<String>> importCustomIcons({String group = 'Mis iconos'}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'svg', 'zip'],
    allowMultiple: true,
  );

  if (picked == null || picked.files.isEmpty) return const [];

  final directory = await customIconsDirectory();
  final imported = <String>[];

  for (final item in picked.files) {
    final sourcePath = item.path;
    if (sourcePath == null || sourcePath.isEmpty) continue;

    final source = File(sourcePath);
    if (!await source.exists()) continue;

    final extension = p.extension(sourcePath).toLowerCase();
    if (extension == '.zip') {
      imported.addAll(await importIconArchive(await source.readAsBytes(), group: group));
      continue;
    }
    final originalName = p
        .basenameWithoutExtension(item.name)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final safeName = originalName.isEmpty ? 'icono' : originalName;
    final target = p.join(
      directory.path,
      '${safeName}_${DateTime.now().microsecondsSinceEpoch}$extension',
    );

    final stored = await source.copy(target);
    final key = 'custom:${stored.path}';
    await saveCustomIconGroup(key, group);
    imported.add(key);
  }

  return imported;
}

class IconPickerPage extends StatefulWidget {
  const IconPickerPage({super.key, required this.currentKey});

  final String currentKey;

  @override
  State<IconPickerPage> createState() => _IconPickerPageState();
}

class _IconPickerPageState extends State<IconPickerPage> {
  List<String> _customKeys = const [];
  Map<String, String> _customGroups = const {};
  bool _loadingCustom = true;
  late String _category;
  String _query = '';
  bool _editingColors = false;
  String _view = 'grid';
  String _order = 'original';
  String? _detailKey;
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _detailKey = widget.currentKey;
    _category = isCustomIconKey(widget.currentKey)
        ? 'Mis iconos'
        : appIconChoiceFor(widget.currentKey).category;
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    final keys = await loadCustomIconKeys();
    final groups = await loadCustomIconGroups(keys);
    if (!mounted) return;
    setState(() {
      _customKeys = keys;
      _customGroups = groups;
      if (_loadingCustom)
        _category = iconCategoryForKey(widget.currentKey, groups);
      if (!iconFilters.contains(_category))
        _category = iconCategoryForKey(widget.currentKey, groups);
      _loadingCustom = false;
    });
  }

  Future<void> _editColors(String key) async {
    if (_editingColors || !canEditIconColors(key)) return;
    _editingColors = true;
    try {
      final appearance = await showDialog<IconAppearance>(
        context: context,
        builder: (_) => IconColorsDialog(iconKey: key),
      );
      if (appearance == null) return;
      await saveIconAppearance(key, appearance);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron guardar los colores.')),
      );
    } finally {
      _editingColors = false;
    }
  }


  Future<void> _select(String key) async {
    if (_selecting) return;
    _selecting = true;
    try {
      await recordRecentIcon(key);
    } catch (_) {
      // Choosing an icon remains available if recent-history storage fails.
    } finally {
      if (mounted) Navigator.pop(context, key);
      _selecting = false;
    }
  }

  Future<void> _favorite(String key) async {
    if (_editingColors || _selecting) return;
    _editingColors = true;
    try {
      await updateIconSettings(key, favorite: !isIconFavorite(key));
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el favorito.')));
    } finally {
      _editingColors = false;
    }
  }

  Widget _preview(String key, {bool enlarged = false}) {
    final custom = isCustomIconKey(key);
    final svgCircle = isEditableSvgIcon(key);
    final color = iconAppearance(key).line;
    return Container(
      width: enlarged ? 80 : custom ? 48 : 44,
      height: enlarged ? 80 : custom ? 48 : 44,
      padding: custom
          ? const EdgeInsets.all(4)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: iconAppearance(key).circle,
        borderRadius: custom && !svgCircle
            ? BorderRadius.circular(10)
            : null,
        shape: custom && !svgCircle
            ? BoxShape.rectangle
            : BoxShape.circle,
      ),
      child: iconWidgetForKey(
        key,
        color: color,
        size: enlarged ? 50 : custom
            ? (svgCircle ? 26 : 40)
            : isElectricCollectionKey(key)
            ? 22
            : 28,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builtInVisible = appIconChoices
        .where(
          (choice) =>
              !isIconHidden(choice.key) &&
              (_category == 'Todos' ||
                  (_category == 'Favoritos' && isIconFavorite(choice.key)) ||
                  iconCategoryForKey(choice.key) == _category),
        )
        .where((choice) => appIconLabel(choice.key).toLowerCase()
            .contains(_query.trim().toLowerCase()))
        .toList();
    final showingCustom = _category == 'Mis iconos';
    final filteredKeys = <String>[
      if (!showingCustom) ...builtInVisible.map((choice) => choice.key),
      ..._customKeys.where(
        (key) =>
            !isIconHidden(key) &&
            appIconLabel(key).toLowerCase().contains(_query.trim().toLowerCase()) &&
            (_category == 'Todos' ||
                (_category == 'Favoritos' && isIconFavorite(key)) ||
                iconCategoryForKey(key, _customGroups) == _category),
      ),
      if (showingCustom) ...builtInVisible.map((choice) => choice.key),
    ];
    final visibleKeys = orderedIconKeys(filteredKeys, _order, _customGroups);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Seleccionar icono',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('icon_picker_view'),
            tooltip: 'Vista',
            icon: const Icon(Icons.view_module_outlined),
            onSelected: (value) => setState(() => _view = value),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'grid', checked: _view == 'grid',
                child: const Text('Cuadrícula')),
              CheckedPopupMenuItem(value: 'compact', checked: _view == 'compact',
                child: const Text('Conjunto compacto')),
              CheckedPopupMenuItem(value: 'list', checked: _view == 'list',
                child: const Text('Lista')),
              CheckedPopupMenuItem(value: 'gallery', checked: _view == 'gallery',
                child: const Text('Galería ampliada')),
              CheckedPopupMenuItem(value: 'colors', checked: _view == 'colors',
                child: const Text('Por colores')),
              CheckedPopupMenuItem(value: 'detail', checked: _view == 'detail',
                child: const Text('Detalle')),
              CheckedPopupMenuItem(value: 'quick', checked: _view == 'quick',
                child: const Text('Favoritos y recientes')),
            ],
          ),
          _IconOrderMenu(order: _order,
            onSelected: (value) => setState(() => _order = value)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar iconos',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: iconFilters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final item = iconFilters[index];
                  return ChoiceChip(
                    label: Text(item),
                    selected: _category == item,
                    onSelected: (_) => setState(() => _category = item),
                  );
                },
              ),
            ),
            if (canEditIconColors(widget.currentKey))
              TextButton.icon(
                key: const ValueKey('picker_edit_current_colors'),
                onPressed: () => _editColors(widget.currentKey),
                icon: const Icon(Icons.palette_outlined),
                label: const Text('Colores del icono actual'),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Mantén pulsado un icono para cambiar sus colores.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF6F747A)),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = _view == 'compact';
                  final gallery = _view == 'gallery';
                  final columns = (constraints.maxWidth / (compact ? 64 : gallery ? 150 : 88))
                      .floor().clamp(2, compact ? 12 : gallery ? 4 : 6);
                  final labelSize = MediaQuery.textScalerOf(context).scale(gallery ? 13 : 11);
                  final gridDelegate =
                      SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        // Padding + icono + separación + dos líneas + margen.
                        mainAxisExtent: compact ? 64 : 16 + (gallery ? 80 : 48) + 6 + labelSize * 2.4 + 8,
                      );
                  if (_loadingCustom && showingCustom) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (visibleKeys.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No hay iconos que coincidan. Puedes preparar nuevos '
                          'iconos desde el gestor del menú principal.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (_view == 'detail') {
                    final index = visibleKeys.contains(_detailKey)
                        ? visibleKeys.indexOf(_detailKey!) : 0;
                    final key = visibleKeys[index];
                    return _IconDetailCard(
                      iconKey: key, group: iconCategoryForKey(key, _customGroups),
                      position: index, total: visibleKeys.length,
                      onPrevious: index > 0
                          ? () => setState(() => _detailKey = visibleKeys[index - 1]) : null,
                      onNext: index + 1 < visibleKeys.length
                          ? () => setState(() => _detailKey = visibleKeys[index + 1]) : null,
                      onColors: canEditIconColors(key) ? () => _editColors(key) : null,
                      onFavorite: () => _favorite(key),
                      onSelect: () => _select(key),
                    );
                  }
                  if (_view == 'list') {
                    return ListView.separated(
                      key: const ValueKey('icon_picker_list'),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: visibleKeys.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final key = visibleKeys[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            leading: _preview(key),
                            title: Text(appIconLabel(key)),
                            selected: key == widget.currentKey,
                            selectedTileColor: iconAppearance(key).line.withValues(alpha: 0.12),
                            trailing: key == widget.currentKey
                                ? const Icon(Icons.check) : null,
                            onTap: () => _select(key),
                            onLongPress: canEditIconColors(key)
                                ? () => _editColors(key) : null,
                          ),
                        );
                      },
                    );
                  }
                  Widget tile(String key) {
                      final selected = key == widget.currentKey;
                      final color = iconAppearance(key).line;
                      return Tooltip(
                        message: appIconLabel(key),
                        triggerMode: TooltipTriggerMode.manual,
                        child: Semantics(
                          label: compact ? appIconLabel(key) : null,
                          button: true,
                          selected: selected,
                          child: Material(
                        color: selected
                            ? color.withValues(alpha: 0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _select(key),
                          onLongPress: canEditIconColors(key)
                              ? () => _editColors(key)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _preview(key, enlarged: gallery),
                                if (!compact) const SizedBox(height: 6),
                                if (!compact) Text(
                                  appIconLabel(key),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: gallery ? 13 : isCustomIconKey(key) ? 10 : 11,
                                    height: 1.2,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                          ),
                        ),
                      );
                  }

                  if (_view == 'quick') {
                    return _IconQuickView(keys: visibleKeys, gridDelegate: gridDelegate,
                      tileBuilder: tile);
                  }
                  if (_view == 'colors') {
                    final groups = <String, List<String>>{};
                    for (final key in visibleKeys) {
                      groups.putIfAbsent(iconBackgroundColorGroup(key), () => []).add(key);
                    }
                    return CustomScrollView(
                      key: const ValueKey('icon_picker_colors'),
                      slivers: [
                        for (final group in iconBackgroundGroups)
                          if (groups.containsKey(group)) ...[
                            SliverToBoxAdapter(child: _iconColorHeading(group, groups[group]!.length,
                              ValueKey('icon_picker_color_$group'))),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              sliver: SliverGrid(
                                gridDelegate: gridDelegate,
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => tile(groups[group]![index]),
                                  childCount: groups[group]!.length,
                                ),
                              ),
                            ),
                          ],
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    );
                  }
                  return GridView.builder(
                    key: ValueKey('icon_picker_$_view'),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    gridDelegate: gridDelegate,
                    itemCount: visibleKeys.length,
                    itemBuilder: (context, index) => tile(visibleKeys[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class IconColorsDialog extends StatefulWidget {
  const IconColorsDialog({super.key, required this.iconKey});
  final String iconKey;
  @override
  State<IconColorsDialog> createState() => _IconColorsDialogState();
}
class _IconColorsDialogState extends State<IconColorsDialog> {
  late Color _lines;
  late Color _circle;
  @override
  void initState() {
    super.initState();
    final initial = iconAppearance(widget.iconKey);
    _lines = initial.line;
    _circle = initial.circle;
  }
  Widget _palette(bool background) => Wrap(
    spacing: 8, runSpacing: 8,
    children: [
      for (final value in optionColorPalette)
        InkWell(
          key: ValueKey('icon_${background ? "circle" : "line"}_$value'),
          borderRadius: BorderRadius.circular(22),
          onTap: () => setState(() {
            if (background) {
              _circle = Color(value).withValues(alpha: 0.16);
            } else {
              _lines = Color(value);
            }
          }),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background ? Color(value).withValues(alpha: 0.16) : Color(value),
              border: Border.all(
                width: 2,
                color: (background ? _circle : _lines).toARGB32() ==
                  (background ? Color(value).withValues(alpha: 0.16) : Color(value)).toARGB32()
                    ? const Color(0xFF20242A) : Colors.transparent,
              ),
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Colores del icono'),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            key: const ValueKey('icon_color_preview'),
            width: 80, height: 80,
            decoration: BoxDecoration(color: _circle, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: iconWidgetForKey(widget.iconKey, color: _lines,
                circleColor: _circle, size: 44),
          ),
          const SizedBox(height: 18),
          const Text('Color del círculo'),
          const SizedBox(height: 10),
          _palette(true),
          const SizedBox(height: 18),
          const Text('Color de las líneas'),
          const SizedBox(height: 10),
          _palette(false),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar')),
      FilledButton(
        onPressed: () => Navigator.pop(context,
            IconAppearance(_lines.toARGB32(), _circle.toARGB32())),
        child: const Text('Guardar'),
      ),
    ],
  );
}

Future<List<String>> importIconArchive(List<int> bytes,
    {String group = 'Mis iconos'}) async {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('El ZIP es demasiado grande');
  }
  final archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));
  if (archive.files.length > 1024 ||
      archive.files.fold<int>(0, (sum, file) => sum + file.size) > 50 * 1024 * 1024) {
    throw const FormatException('El paquete es demasiado grande');
  }
  final metadata = <String, Map>{};
  for (final file in archive.files) {
    if (file.isFile && p.posix.basename(file.name) == 'catalogo.json') {
      final catalog = jsonDecode(utf8.decode(file.content));
      if (catalog is Map && catalog['iconos'] is List) {
        for (final entry in catalog['iconos'] as List) {
          if (entry is Map && entry['archivo'] is String) {
            metadata[p.posix.basename(entry['archivo'] as String)] = entry;
          }
        }
      }
    }
  }
  final packed = metadata.isNotEmpty && archive.files.any(
    (file) => file.isFile && file.name.startsWith('iconos/'));
  final candidates = archive.files.where((file) =>
    file.isFile &&
    (!packed || file.name.startsWith('iconos/')) &&
    !p.posix.basename(file.name).startsWith('vista_previa') &&
    ['.svg', '.png', '.jpg', '.jpeg', '.webp']
        .contains(p.posix.extension(file.name).toLowerCase())).toList();
  if (candidates.length > 512) throw const FormatException('Demasiados iconos');
  final directory = await customIconsDirectory();
  final imported = <String>[];
  for (final file in candidates) {
    if (file.size > 5 * 1024 * 1024) {
      throw const FormatException('Un icono es demasiado grande');
    }
    final original = p.posix.basename(file.name);
    final extension = p.posix.extension(original).toLowerCase();
    final safeName = p.posix.basenameWithoutExtension(original)
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final target = File(p.join(directory.path,
        '${safeName.isEmpty ? "icono" : safeName}_${DateTime.now().microsecondsSinceEpoch}$extension'));
    await target.writeAsBytes(file.content, flush: true);
    final key = 'custom:${target.path}';
    await saveCustomIconGroup(key, group);
    final entry = metadata[original];
    final label = entry?['nombre'];
    if (label is String && label.trim().isNotEmpty) {
      await saveIconName(key, label.trim());
    } else {
      await saveIconName(key, p.posix.basenameWithoutExtension(original).replaceAll('_', ' '));
    }
    int? parseColor(dynamic value) {
      if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return null;
      return int.parse('ff${value.substring(1)}', radix: 16);
    }
    if (extension == '.svg') {
      final current = iconAppearance(key);
      await saveIconAppearance(key, IconAppearance(
        parseColor(entry?['color_lineas']) ?? current.lineValue,
        parseColor(entry?['color_fondo']) ?? current.circleValue,
      ));
    }
    imported.add(key);
  }
  return imported;
}

class IconManagementPage extends StatefulWidget {
  const IconManagementPage({super.key});
  @override
  State<IconManagementPage> createState() => _IconManagementPageState();
}



const iconBackgroundGroups = <String>[
  'Rojos', 'Naranjas', 'Amarillos', 'Verdes', 'Turquesas', 'Azules',
  'Violetas', 'Rosas', 'Blancos', 'Grises', 'Negros', 'Sin fondo',
];

String iconBackgroundColorGroup(String key) {
  final color = iconAppearance(key).circle;
  if (color.a == 0) return 'Sin fondo';
  final hsv = HSVColor.fromColor(color);
  if (hsv.saturation < 0.08) {
    if (hsv.value < 0.25) return 'Negros';
    if (hsv.value > 0.90) return 'Blancos';
    return 'Grises';
  }
  final hue = hsv.hue;
  if (hue < 15 || hue >= 345) return 'Rojos';
  if (hue < 45) return 'Naranjas';
  if (hue < 75) return 'Amarillos';
  if (hue < 170) return 'Verdes';
  if (hue < 195) return 'Turquesas';
  if (hue < 255) return 'Azules';
  if (hue < 290) return 'Violetas';
  return 'Rosas';
}

Widget _iconColorHeading(String group, int count, Key key) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
  child: Text('$group · $count', key: key,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
);

String _iconOrderText(String value) => value.toLowerCase()
    .replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i')
    .replaceAll('ó', 'o').replaceAll('ú', 'u').replaceAll('ü', 'u')
    .replaceAll('ñ', 'n~');

List<String> orderedIconKeys(Iterable<String> keys, String order,
    [Map<String, String> groups = const {}]) {
  final result = keys.toList();
  if (order == 'original') return result;
  final positions = {for (var i = 0; i < result.length; i++) result[i]: i};
  result.sort((a, b) {
    int comparison = 0;
    if (order == 'favorites') {
      comparison = (isIconFavorite(b) ? 1 : 0).compareTo(isIconFavorite(a) ? 1 : 0);
    } else if (order == 'group') {
      comparison = _iconOrderText(iconCategoryForKey(a, groups))
          .compareTo(_iconOrderText(iconCategoryForKey(b, groups)));
    }
    if (comparison == 0) {
      comparison = _iconOrderText(appIconLabel(a)).compareTo(_iconOrderText(appIconLabel(b)));
      if (order == 'za') comparison = -comparison;
    }
    return comparison != 0 ? comparison : positions[a]!.compareTo(positions[b]!);
  });
  return result;
}

class _IconOrderMenu extends StatelessWidget {
  const _IconOrderMenu({required this.order, required this.onSelected});
  final String order;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Ordenar',
    icon: const Icon(Icons.sort),
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final entry in (const {
        'original': 'Orden original',
        'az': 'Nombre: A–Z',
        'za': 'Nombre: Z–A',
        'group': 'Grupo y nombre',
        'favorites': 'Favoritos primero',
      }).entries)
        CheckedPopupMenuItem(value: entry.key, checked: order == entry.key,
          child: Text(entry.value)),
    ],
  );
}

class _IconManagementPageState extends State<IconManagementPage> {
  List<String> _keys = [];
  Map<String, String> _groups = {};
  String _query = '';
  String _group = 'Todos';
  bool _trash = false;
  bool _loading = true;
  bool _saving = false;
  String _view = 'list';
  String _order = 'original';
  String? _detailKey;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final custom = await loadCustomIconKeys();
    final groups = await loadCustomIconGroups(custom);
    if (!mounted) return;
    setState(() {
      _keys = [...appIconChoices.map((i) => i.key), ...custom];
      _groups = groups;
      _loading = false;
    });
  }

  Future<void> _change(String key, String action) async {
    if (_saving) return;
    _saving = true;
    try {
      if (action == 'rename') {
        if (!await showIconRename(context, key)) return;
      } else if (action == 'colors') {
        final result = await showDialog<IconAppearance>(
          context: context,
          builder: (_) => IconColorsDialog(iconKey: key),
        );
        if (result == null) return;
        await saveIconAppearance(key, result);
      } else if (action == 'favorite') {
        await updateIconSettings(key, favorite: !isIconFavorite(key));
      } else if (action == 'group') {
        final group = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Mover a un grupo'),
            children: [
              for (final group in iconGroups)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, group),
                  child: Text(group),
                ),
            ],
          ),
        );
        if (group == null) return;
        await updateIconSettings(key, group: group);
      } else if (action == 'delete') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Eliminar «${appIconLabel(key)}»'),
            content: const Text(
              'Se moverá a la papelera. Las herramientas que ya lo usan conservarán su icono.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await updateIconSettings(key, hidden: true);
      } else if (action == 'restore') {
        await updateIconSettings(key, hidden: false);
      }
      if (mounted) await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el cambio. Inténtalo de nuevo.'),
        ),
      );
    } finally {
      _saving = false;
    }
  }


  Future<void> _emptyTrash() async {
    if (_saving || _loading) return;
    final count = _keys.where((key) => isIconHidden(key) && !isIconRemoved(key)).length;
    if (count == 0) return;
    setState(() => _saving = true);
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Vaciar papelera'),
          content: Text('Se retirarán definitivamente los $count iconos de toda la papelera, '
              'incluidos los que no aparecen por los filtros. No podrás restaurarlos desde el gestor. '
              'Los iconos asignados a tipos o estados se conservarán para que las herramientas sigan mostrándolos.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Vaciar papelera')),
          ],
        ),
      );
      if (confirm != true) return;
      final result = await emptyIconTrash();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.keptForUsage == 0
            ? 'Papelera vaciada: ${result.emptied} iconos.'
            : 'Papelera vaciada. ${result.keptForUsage} iconos siguen disponibles en las herramientas que los usan.'),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo vaciar la papelera. Inténtalo de nuevo.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _import() async {
    try {
      final imported = await importCustomIcons(
        group: iconGroups.contains(_group) ? _group : 'Mis iconos',
      );
      if (!mounted) return;
      if (imported.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${imported.length} iconos importados')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo importar el archivo de iconos.')),
      );
    }
    if (mounted) await _load();
  }


  Widget _list(List<String> keys) {
    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      itemCount: keys.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final key = keys[index];
                        final color = iconAppearance(key).line;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: iconAppearance(key).circle,
                              child: iconWidgetForKey(
                                key,
                                color: color,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              appIconLabel(key),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(iconCategoryForKey(key, _groups)),
                            onTap: () =>
                                _change(key, _trash ? 'restore' : 'rename'),
                            onLongPress: canEditIconColors(key) && !_trash
                                ? () => _change(key, 'colors') : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_trash)
                                  IconButton(
                                    tooltip: isIconFavorite(key)
                                        ? 'Quitar de favoritos'
                                        : 'Añadir a favoritos',
                                    icon: Icon(
                                      isIconFavorite(key)
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: isIconFavorite(key)
                                          ? Colors.amber.shade800
                                          : null,
                                    ),
                                    onPressed: () => _change(key, 'favorite'),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: 'Opciones del icono',
                                  onSelected: (action) => _change(key, action),
                                  itemBuilder: (_) => _trash
                                      ? const [
                                          PopupMenuItem(
                                            value: 'restore',
                                            child: Text('Restaurar'),
                                          ),
                                        ]
                                      : [
                                          if (canEditIconColors(key))
                                            const PopupMenuItem(
                                              value: 'colors',
                                              child: Text('Cambiar colores'),
                                            ),
                                          const PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Cambiar nombre'),
                                          ),
                                          PopupMenuItem(
                                            value: 'group',
                                            child: Text('Cambiar grupo'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Eliminar'),
                                          ),
                                        ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
  }

  Map<String, String> _actions(String key) => _trash
      ? {'restore': 'Restaurar'}
      : {
          if (canEditIconColors(key)) 'colors': 'Cambiar colores',
          'rename': 'Cambiar nombre',
          'favorite': isIconFavorite(key) ? 'Quitar de favoritos' : 'Añadir a favoritos',
          'group': 'Cambiar grupo',
          'delete': 'Eliminar',
        };

  Future<void> _showActions(String key) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16),
              child: Text(appIconLabel(key), style: Theme.of(context).textTheme.titleMedium)),
            for (final entry in _actions(key).entries)
              ListTile(title: Text(entry.value),
                onTap: () => Navigator.pop(context, entry.key)),
          ],
        )),
      ),
    );
    if (action != null && mounted) await _change(key, action);
  }

  Widget _tile(String key, bool compact) {
    final label = appIconLabel(key);
    final gallery = _view == 'gallery';
    return Semantics(
      label: compact ? label : null,
      button: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showActions(key),
          onLongPress: canEditIconColors(key) && !_trash
              ? () => _change(key, 'colors') : () => _showActions(key),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(children: [
                CircleAvatar(
                  radius: gallery ? 40 : 22,
                  backgroundColor: iconAppearance(key).circle,
                  child: iconWidgetForKey(key, color: iconAppearance(key).line, size: gallery ? 50 : 26),
                ),
                if (isIconFavorite(key))
                  const Positioned(right: 0, top: 0,
                    child: Icon(Icons.star, size: 12, color: Color(0xFFB77900))),
              ]),
              if (!compact) ...[
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, maxLines: 2,
                  overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: gallery ? 13 : 11, height: 1.2)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _collection(List<String> keys) {
    if (_view == 'list') return _list(keys);
    if (_view == 'detail') {
      final index = keys.contains(_detailKey) ? keys.indexOf(_detailKey!) : 0;
      final key = keys[index];
      return _IconDetailCard(
        iconKey: key, group: iconCategoryForKey(key, _groups),
        position: index, total: keys.length,
        onPrevious: index > 0 ? () => setState(() => _detailKey = keys[index - 1]) : null,
        onNext: index + 1 < keys.length ? () => setState(() => _detailKey = keys[index + 1]) : null,
        onColors: !_trash && canEditIconColors(key) ? () => _change(key, 'colors') : null,
        onFavorite: !_trash ? () => _change(key, 'favorite') : null,
        onManage: !_trash ? () => _showActions(key) : null,
        onRestore: _trash ? () => _change(key, 'restore') : null,
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final compact = _view == 'compact';
      final gallery = _view == 'gallery';
      final columns = (constraints.maxWidth / (compact ? 64 : gallery ? 150 : 100))
          .floor().clamp(2, compact ? 12 : gallery ? 4 : 6);
      final labelSize = MediaQuery.textScalerOf(context).scale(gallery ? 13 : 11);
      final delegate = SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns, mainAxisSpacing: 8, crossAxisSpacing: 8,
        mainAxisExtent: compact ? 64 : 16 + (gallery ? 80 : 44) + 6 + labelSize * 2.4 + 8,
      );
      Widget grid(List<String> items) => SliverGrid(
        gridDelegate: delegate,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _tile(items[index], compact),
          childCount: items.length,
        ),
      );
      if (_view == 'quick') {
        return _IconQuickView(keys: keys, gridDelegate: delegate,
          includeHidden: _trash, tileBuilder: (key) => _tile(key, false));
      }
      final groups = <String, List<String>>{};
      if (_view == 'groups' || _view == 'colors') {
        for (final key in keys) {
          final group = _view == 'colors' ? iconBackgroundColorGroup(key)
              : iconCategoryForKey(key, _groups);
          groups.putIfAbsent(group, () => []).add(key);
        }
      }
      final names = groups.keys.toList()..sort((a, b) => _view == 'colors'
          ? iconBackgroundGroups.indexOf(a).compareTo(iconBackgroundGroups.indexOf(b))
          : a.toLowerCase().compareTo(b.toLowerCase()));
      return CustomScrollView(
        key: ValueKey('icon_manager_$_view'),
        slivers: [
          if (_view == 'groups' || _view == 'colors')
            for (final name in names) ...[
              SliverToBoxAdapter(child: _view == 'colors'
                  ? _iconColorHeading(name, groups[name]!.length,
                      ValueKey('icon_manager_color_$name'))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('$name · ${groups[name]!.length}',
                        key: ValueKey('icon_manager_group_$name'),
                        style: Theme.of(context).textTheme.titleMedium),
                    )),
              SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: grid(groups[name]!)),
            ]
          else
            SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: grid(keys)),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _keys
        .where(
          (key) =>
              !isIconRemoved(key) &&
              isIconHidden(key) == _trash &&
              (_group == 'Todos' ||
                  (_group == 'Favoritos' && isIconFavorite(key)) ||
                  iconCategoryForKey(key, _groups) == _group) &&
              appIconLabel(key)
                  .toLowerCase()
                  .contains(_query.trim().toLowerCase()),
        )
        .toList();
    final visible = orderedIconKeys(filtered, _order, _groups);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestor de iconos'),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('icon_manager_view'),
            tooltip: 'Vista',
            icon: const Icon(Icons.view_module_outlined),
            onSelected: (value) => setState(() => _view = value),
            itemBuilder: (_) => [
              for (final entry in (const {'grid': 'Cuadrícula', 'compact': 'Conjunto compacto', 'list': 'Lista', 'groups': 'Por grupos', 'gallery': 'Galería ampliada', 'colors': 'Por colores', 'detail': 'Detalle', 'quick': 'Favoritos y recientes'}).entries)
                CheckedPopupMenuItem(value: entry.key, checked: _view == entry.key,
                  child: Text(entry.value)),
            ],
          ),

          _IconOrderMenu(order: _order,
            onSelected: (value) => setState(() => _order = value)),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Grupos',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const IconGroupsPage()),
              );
              if (!mounted) return;
              if (!iconFilters.contains(_group)) _group = 'Todos';
              await _load();
            },
          ),
        ],
      ),
      floatingActionButton: _trash
          ? null
          : FloatingActionButton.extended(
              onPressed: _import,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Importar'),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar iconos',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                key: ValueKey(_group),
                initialValue: _group,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Grupo'),
                items: iconFilters
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _group = value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Iconos activos'),
                    selected: !_trash,
                    onSelected: (_) => setState(() => _trash = false),
                  ),
                  ChoiceChip(
                    label: const Text('Papelera'),
                    selected: _trash,
                    onSelected: (_) => setState(() => _trash = true),
                  ),
                ],
              ),
            ),
            if (_trash)
              TextButton.icon(
                key: const ValueKey('empty_icon_trash'),
                onPressed: _saving || _loading || !_keys.any((key) => isIconHidden(key) && !isIconRemoved(key))
                    ? null : _emptyTrash,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Vaciar papelera'),
              ),
            Text(
              '${visible.length} iconos',
              style: const TextStyle(color: Color(0xFF6F747A)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? Center(
                      child: Text(
                        _trash
                            ? 'La papelera está vacía'
                            : 'No hay iconos que coincidan',
                      ),
                    )
                  : _collection(visible),
            ),
          ],
        ),
      ),
    );
  }
}

class IconGroupsPage extends StatefulWidget {
  const IconGroupsPage({super.key});
  @override
  State<IconGroupsPage> createState() => _IconGroupsPageState();
}

class _IconGroupsPageState extends State<IconGroupsPage> {
  bool _busy = false;
  Future<void> _edit([String? original]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _IconGroupDialog(original: original),
    );
    if (name == null || !mounted) return;
    await _save(() => saveIconGroup(name, original: original));
  }

  Future<void> _save(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar el grupo. Inténtalo de nuevo.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar «$group»'),
        content: const Text(
          'Sus iconos pasarán a Mis iconos. Se conservarán sus nombres y favoritos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar grupo'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _save(() => deleteIconGroup(group));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Grupos de iconos')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy ? null : () => _edit(),
      icon: const Icon(Icons.create_new_folder_outlined),
      label: const Text('Crear grupo'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Crea grupos como Carpintería, Fontanería o Medición. Después mueve tus iconos desde el gestor.',
            ),
          ),
          for (final group in iconGroups)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(group),
                subtitle: Text(
                  _customIconCategories.contains(group)
                      ? 'Grupo personalizado'
                      : 'Grupo de la aplicación',
                ),
                trailing: _customIconCategories.contains(group)
                    ? PopupMenuButton<String>(
                        enabled: !_busy,
                        tooltip: 'Opciones del grupo',
                        onSelected: (action) =>
                            action == 'rename' ? _edit(group) : _delete(group),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Cambiar nombre'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar grupo'),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
        ],
      ),
    ),
  );
}

class _IconGroupDialog extends StatefulWidget {
  const _IconGroupDialog({this.original});
  final String? original;
  @override
  State<_IconGroupDialog> createState() => _IconGroupDialogState();
}

class _IconGroupDialogState extends State<_IconGroupDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.original ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate())
      Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.original == null ? 'Crear grupo' : 'Cambiar nombre del grupo',
    ),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: 'Nombre del grupo'),
        validator: (value) =>
            iconGroupNameError(value ?? '', original: widget.original),
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar')),
    ],
  );
}

class _IconRenameDialog extends StatefulWidget {
  const _IconRenameDialog({required this.iconKey});
  final String iconKey;
  @override
  State<_IconRenameDialog> createState() => _IconRenameDialogState();
}

class _IconRenameDialogState extends State<_IconRenameDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: appIconLabel(widget.iconKey));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate())
      Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cambiar nombre del icono'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Nombre del icono'),
        textCapitalization: TextCapitalization.sentences,
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Escribe un nombre' : null,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('Nombre original'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}

class FieldOptionEditPage extends StatefulWidget {
  const FieldOptionEditPage({
    super.key,
    required this.fieldKey,
    required this.position,
    this.existing,
  });

  final String fieldKey;
  final int position;
  final FieldOption? existing;

  @override
  State<FieldOptionEditPage> createState() => _FieldOptionEditPageState();
}

class _FieldOptionEditPageState extends State<FieldOptionEditPage> {
  late final TextEditingController _controller;
  late String _iconKey;
  late int _colorValue;
  int? _circleColorValue;

  String get _title => widget.fieldKey == 'type' ? 'Tipo' : 'Estado';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existing?.label ?? '');
    _iconKey =
        widget.existing?.iconKey ??
        (widget.fieldKey == 'type' ? 'category' : 'check');
    _circleColorValue = widget.existing?.circleColorValue;
    _colorValue =
        widget.existing?.colorValue ??
        (widget.fieldKey == 'type' ? 0xFF1976D2 : 0xFF43A047);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _chooseIcon() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => IconPickerPage(currentKey: _iconKey)),
    );
    if (!mounted) return;
    if (selected == null) {
      setState(() {});
      return;
    }

    setState(() {
      _iconKey = selected;
      _colorValue = iconAppearance(selected).lineValue;
      if (hasIconCircle(selected)) {
        _circleColorValue = iconAppearance(selected).circleValue;
      }
    });
  }

  void _save() {
    final label = _controller.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un nombre para la opción')),
      );
      return;
    }

    Navigator.pop(
      context,
      FieldOption(
        id: widget.existing?.id,
        fieldKey: widget.fieldKey,
        label: label,
        iconKey: _iconKey,
        colorValue: _colorValue,
        circleColorValue: _circleColorValue,
        position: widget.existing?.position ?? widget.position,
        active: widget.existing?.active ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Nueva opción de $_title'
              : 'Editar $_title',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'GUARDAR',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
          children: [
            TextField(
              controller: _controller,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _chooseIcon,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
              ),
              child: Row(
                children: [
                  fieldOptionIconWidget(
                    FieldOption(
                      fieldKey: widget.fieldKey,
                      label: '',
                      iconKey: _iconKey,
                      colorValue: _colorValue,
                      circleColorValue: _circleColorValue,
                    ),
                    size: hasIconCircle(_iconKey) ? 44 : 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Icono: ${appIconLabel(_iconKey)}',
                      textAlign: TextAlign.left,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Los nombres, grupos y colores de los iconos se editan '
              'en el Gestor de iconos del menú principal.',
              style: TextStyle(color: Color(0xFF6F747A), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class FieldOptionsManagementPage extends StatefulWidget {
  const FieldOptionsManagementPage({super.key});

  @override
  State<FieldOptionsManagementPage> createState() =>
      _FieldOptionsManagementPageState();
}

class _FieldOptionsManagementPageState
    extends State<FieldOptionsManagementPage> {
  String _fieldKey = 'type';
  List<FieldOption> _options = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final options = await ToolsDatabase.instance.loadFieldOptions(
      _fieldKey,
      includeInactive: true,
    );
    if (!mounted) return;
    setState(() {
      _options = options;
      _loading = false;
    });
  }

  Future<void> _editOption([FieldOption? existing]) async {
    final result = await Navigator.of(context).push<FieldOption>(
      MaterialPageRoute(
        builder: (_) => FieldOptionEditPage(
          fieldKey: _fieldKey,
          position: _options.length,
          existing: existing,
        ),
      ),
    );
    if (!mounted || result == null) return;

    try {
      await ToolsDatabase.instance.saveFieldOption(
        result,
        previousLabel: existing?.label,
      );
      await _load();
    } on DatabaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.isUniqueConstraintError()
                ? 'Ya existe una opción con ese nombre.'
                : 'No se pudo guardar la opción.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteOption(FieldOption option) async {
    final usage = await ToolsDatabase.instance.countFieldOptionUsage(option);
    if (!mounted) return;

    String? replacement;
    if (usage > 0) {
      final alternatives = _options
          .where((item) => item.id != option.id)
          .toList();
      if (alternatives.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se puede eliminar la única opción mientras esté en uso.',
            ),
          ),
        );
        return;
      }

      replacement = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          var value = alternatives.first.label;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Opción en uso'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hay $usage herramientas que usan “${option.label}”. '
                    'Selecciona a qué opción deben pasar.',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: value,
                    decoration: const InputDecoration(
                      labelText: 'Reemplazar por',
                    ),
                    items: alternatives
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.label,
                            child: Row(
                              children: [
                                fieldOptionIconWidget(item, size: 20),
                                const SizedBox(width: 8),
                                Text(item.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (newValue) {
                      if (newValue == null) return;
                      setDialogState(() => value = newValue);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, value),
                  child: const Text('Reemplazar y eliminar'),
                ),
              ],
            ),
          );
        },
      );

      if (replacement == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Eliminar opción'),
          content: Text('¿Eliminar “${option.label}”?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await ToolsDatabase.instance.deleteFieldOption(
      option,
      replacementLabel: replacement,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configurar Tipo y Estado',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editOption(),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const SizedBox(
                        width: double.infinity,
                        child: Text('Tipo', textAlign: TextAlign.center),
                      ),
                      selected: _fieldKey == 'type',
                      onSelected: (_) {
                        setState(() {
                          _fieldKey = 'type';
                          _loading = true;
                        });
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const SizedBox(
                        width: double.infinity,
                        child: Text('Estado', textAlign: TextAlign.center),
                      ),
                      selected: _fieldKey == 'condition',
                      onSelected: (_) {
                        setState(() {
                          _fieldKey = 'condition';
                          _loading = true;
                        });
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Puedes crear nuevas opciones y modificar su nombre, icono '
                  'y color. Si renombras una opción, las herramientas '
                  'existentes se actualizan automáticamente.',
                  style: TextStyle(color: Color(0xFF6F747A), fontSize: 13),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _options.isEmpty
                  ? const Center(child: Text('No hay opciones'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 92),
                      itemCount: _options.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final option = _options[index];
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: isElectricCollectionKey(option.iconKey)
                                ? fieldOptionIconWidget(option, size: 40)
                                : CircleAvatar(
                                    backgroundColor: option.circleColor,
                                    child: fieldOptionIconWidget(
                                      option,
                                      size: 24,
                                    ),
                                  ),
                            title: Text(
                              option.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              'Icono: ${appIconLabel(option.iconKey)}',
                            ),
                            onTap: () => _editOption(option),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editOption(option);
                                } else if (value == 'delete') {
                                  _deleteOption(option);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Eliminar'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class DatabaseManagementPage extends StatefulWidget {
  const DatabaseManagementPage({
    super.key,
    required this.onCreateBackup,
    required this.onRestoreBackup,
  });

  final Future<void> Function() onCreateBackup;
  final Future<bool> Function() onRestoreBackup;

  @override
  State<DatabaseManagementPage> createState() => _DatabaseManagementPageState();
}

class _DatabaseManagementPageState extends State<DatabaseManagementPage> {
  late Future<DatabaseStats> _stats;
  late Future<List<Map<String, Object?>>> _overview;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _stats = ToolsDatabase.instance.getStats();
    _overview = ToolsDatabase.instance.databaseOverview();
  }

  void _refreshUi() {
    setState(_refresh);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<void> _checkIntegrity() async {
    try {
      final result = await ToolsDatabase.instance.integrityCheck();
      if (!mounted) return;

      final ok = result.trim().toLowerCase() == 'ok';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 36,
          ),
          title: Text(
            ok ? 'Base de datos correcta' : 'Resultado de comprobación',
          ),
          content: Text(
            ok ? 'SQLite no ha encontrado errores de integridad.' : result,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo comprobar la base de datos: $error'),
        ),
      );
    }
  }

  Future<void> _restore() async {
    final restored = await widget.onRestoreBackup();
    if (!mounted || !restored) return;
    _refreshUi();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gestión de base de datos',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refreshUi(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              FutureBuilder<DatabaseStats>(
                future: _stats,
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  return Row(
                    children: [
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.handyman_outlined,
                          label: 'Herramientas',
                          value: stats == null ? '—' : '${stats.tools}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.photo_library_outlined,
                          label: 'Imágenes',
                          value: stats == null ? '—' : '${stats.images}',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              FutureBuilder<DatabaseStats>(
                future: _stats,
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  return Row(
                    children: [
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.storage_outlined,
                          label: 'SQLite',
                          value: stats == null
                              ? '—'
                              : _formatBytes(stats.databaseBytes),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DatabaseStatCard(
                          icon: Icons.folder_outlined,
                          label: 'Fotos',
                          value: stats == null
                              ? '—'
                              : _formatBytes(stats.imagesBytes),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              const SectionTitle('Seguridad y mantenimiento'),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Crear copia de seguridad'),
                      subtitle: const Text(
                        'Guarda SQLite y todas las imágenes en un ZIP.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.onCreateBackup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('Restaurar copia'),
                      subtitle: const Text(
                        'Recupera herramientas, campos e imágenes.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _restore,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.health_and_safety_outlined),
                      title: const Text('Comprobar integridad'),
                      subtitle: const Text(
                        'Verifica que la base SQLite no tenga errores.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _checkIntegrity,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: SectionTitle('Registros guardados')),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _refreshUi,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, Object?>>>(
                future: _overview,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No se pudieron leer los registros: ${snapshot.error}',
                      ),
                    );
                  }

                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('No hay herramientas guardadas.'),
                      ),
                    );
                  }

                  return Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var index = 0; index < rows.length; index++) ...[
                          Builder(
                            builder: (context) {
                              final row = rows[index];
                              final id = row['id'] ?? '';
                              final name = (row['name'] as String?) ?? '';
                              final barcode = (row['barcode'] as String?) ?? '';
                              final toolType =
                                  (row['tool_type'] as String?) ?? '';
                              final imageCount =
                                  (row['image_count'] as num?)?.toInt() ?? 0;

                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(child: Text('$id')),
                                title: Text(
                                  name.isEmpty ? 'Sin nombre' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if (toolType.isNotEmpty) toolType,
                                    if ((row['voltage'] as String?)
                                            ?.isNotEmpty ??
                                        false)
                                      row['voltage'] as String,
                                    if (barcode.isNotEmpty) barcode,
                                    '$imageCount imágenes',
                                  ].join(' · '),
                                ),
                              );
                            },
                          ),
                          if (index < rows.length - 1) const Divider(height: 1),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatabaseStatCard extends StatelessWidget {
  const _DatabaseStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD7DDE3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF168BD2)),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF72777D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class EditToolPage extends StatefulWidget {
  const EditToolPage({super.key, required this.item, required this.nextId});

  final ToolItem? item;
  final int nextId;

  @override
  State<EditToolPage> createState() => _EditToolPageState();
}

class _EditToolPageState extends State<EditToolPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late String _descriptionPlain;
  late String _descriptionDelta;
  late final TextEditingController _barcode;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _minimumStock;
  late final TextEditingController _purchasePrice;

  late String _condition;
  late String _type;
  late String _voltage;
  List<FieldOption> _typeOptions = defaultFieldOptions('type');
  List<FieldOption> _conditionOptions = defaultFieldOptions('condition');
  late List<ToolImage> _images;
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isEditing => widget.item != null;

  bool get _showVoltage =>
      isElectricalToolType(_type) ||
      _typeOptions.any(
        (option) => option.label == _type && option.iconKey == 'electrical',
      );

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _name = TextEditingController(text: item?.name ?? '');
    _descriptionPlain = item?.description ?? '';
    _descriptionDelta = item?.descriptionDelta ?? '';
    _barcode = TextEditingController(text: item?.barcode ?? '');
    _quantity = TextEditingController(
      text: item == null ? '1' : formatNumber(item.quantity),
    );
    _unit = TextEditingController(text: item?.unit ?? 'ud');
    _minimumStock = TextEditingController(
      text: item == null ? '0' : formatNumber(item.minimumStock),
    );
    _purchasePrice = TextEditingController(
      text: item == null ? '' : item.purchasePrice.toStringAsFixed(2),
    );
    _condition = item?.condition ?? 'Bueno';
    _type = item?.type ?? '';
    _voltage = item?.voltage ?? '';
    _images =
        item?.images.map((image) => image.copy()).toList() ?? <ToolImage>[];
    _loadFieldOptions();
  }

  Future<void> _loadFieldOptions() async {
    final types = await ToolsDatabase.instance.loadFieldOptions('type');
    final conditions = await ToolsDatabase.instance.loadFieldOptions(
      'condition',
    );
    if (!mounted) return;

    setState(() {
      _typeOptions = types.isEmpty ? defaultFieldOptions('type') : types;
      _conditionOptions = conditions.isEmpty
          ? defaultFieldOptions('condition')
          : conditions;

      if (_condition.isEmpty && _conditionOptions.isNotEmpty) {
        _condition = _conditionOptions.first.label;
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _quantity.dispose();
    _unit.dispose();
    _minimumStock.dispose();
    _purchasePrice.dispose();
    super.dispose();
  }

  double _number(String value) {
    return double.tryParse(value.replaceAll(',', '.').trim()) ?? 0;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final result = ToolItem(
      id: widget.item?.id ?? widget.nextId,
      name: _name.text.trim(),
      description: _descriptionPlain,
      descriptionDelta: _descriptionDelta,
      barcode: _barcode.text.trim(),
      quantity: _number(_quantity.text),
      unit: _unit.text.trim().isEmpty ? 'ud' : _unit.text.trim(),
      minimumStock: _number(_minimumStock.text),
      purchasePrice: _number(_purchasePrice.text),
      condition: _condition,
      type: _type,
      voltage: _showVoltage ? _voltage : '',
      images: _images.map((image) => image.copy()).toList(),
    );

    Navigator.of(context).pop(result);
  }

  Future<Directory> _toolImagesDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'tool_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  void _appendStoredImage(String path) {
    setState(() {
      final image = ToolImage(
        toolId: widget.item?.id ?? widget.nextId,
        path: path,
        position: _images.length,
        isPrimary: _images.isEmpty,
      );
      _images.add(image);
    });
  }

  Future<String> _copyPickedImage(XFile picked) async {
    final imagesDir = await _toolImagesDirectory();
    final extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    final targetPath = p.join(
      imagesDir.path,
      'tool_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    final stored = await File(picked.path).copy(targetPath);
    return stored.path;
  }

  Future<void> _storePickedImage(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final picked = await _imagePicker.pickMultiImage(
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked.isEmpty) return;

      for (final image in picked) {
        final storedPath = await _copyPickedImage(image);
        if (!mounted) return;
        _appendStoredImage(storedPath);
      }
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (picked == null) return;

    final storedPath = await _copyPickedImage(picked);
    if (!mounted) return;
    _appendStoredImage(storedPath);
  }

  Future<void> _downloadImageFromUrl() async {
    final controller = TextEditingController();

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Imagen desde URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'URL de la imagen',
            hintText: 'https://...',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Descargar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (url == null || url.trim().isEmpty) return;

    try {
      final uri = Uri.parse(url.trim());
      if (!(uri.scheme == 'http' || uri.scheme == 'https')) {
        throw const FormatException(
          'La URL debe comenzar por http:// o https://',
        );
      }

      final client = HttpClient();
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'GestorHerramientas/1.0',
      );
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        client.close(force: true);
        throw HttpException('Error HTTP ${response.statusCode}', uri: uri);
      }

      final contentType = response.headers.contentType?.mimeType ?? '';
      if (!contentType.startsWith('image/')) {
        client.close(force: true);
        throw const FormatException('La dirección no devuelve una imagen');
      }

      String extension = p.extension(uri.path).toLowerCase();
      if (extension.isEmpty || extension.length > 6) {
        extension = switch (contentType) {
          'image/png' => '.png',
          'image/webp' => '.webp',
          'image/gif' => '.gif',
          _ => '.jpg',
        };
      }

      final imagesDir = await _toolImagesDirectory();
      final targetPath = p.join(
        imagesDir.path,
        'tool_url_${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      final file = File(targetPath);
      await response.pipe(file.openWrite());
      client.close();

      if (!mounted) return;
      _appendStoredImage(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo descargar la imagen: $error')),
      );
    }
  }

  Future<void> _openAiImageOption() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.auto_awesome, size: 34),
        title: const Text('Imagen con IA'),
        content: const Text(
          'La opción de IA ya está incluida en el gestor. '
          'Para generar imágenes desde la APK falta conectar un servicio de IA '
          'mediante una API segura; no se debe guardar una clave privada dentro de la aplicación.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _setPrimaryImage(ToolImage image) {
    setState(() {
      for (final candidate in _images) {
        candidate.isPrimary = identical(candidate, image);
      }
    });
  }

  void _removeImage(ToolImage image) {
    final wasPrimary = image.isPrimary;
    setState(() {
      _images.remove(image);
      for (var index = 0; index < _images.length; index++) {
        _images[index].position = index;
      }
      if (wasPrimary && _images.isNotEmpty) {
        for (final candidate in _images) {
          candidate.isPrimary = false;
        }
        _images.first.isPrimary = true;
      }
    });
  }

  Future<void> _editImageMetadata(ToolImage image) async {
    final descriptionController = TextEditingController(
      text: image.description,
    );
    var selectedType = image.type;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Datos de la imagen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'General', child: Text('General')),
                  DropdownMenuItem(
                    value: 'Placa',
                    child: Text('Placa de características'),
                  ),
                  DropdownMenuItem(
                    value: 'Avería',
                    child: Text('Avería / incidencia'),
                  ),
                  DropdownMenuItem(
                    value: 'Documento',
                    child: Text('Documento / factura'),
                  ),
                  DropdownMenuItem(value: 'Detalle', child: Text('Detalle')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedType = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción de la imagen',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'type': selectedType,
                'description': descriptionController.text.trim(),
              }),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    descriptionController.dispose();
    if (result == null) return;

    setState(() {
      image.type = result['type'] ?? 'General';
      image.description = result['description'] ?? '';
    });
  }

  Future<void> _openImage(ToolImage image) async {
    if (!File(image.path).existsSync()) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.file(File(image.path), fit: BoxFit.contain),
                ),
              ),
              if (image.description.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(image.description, textAlign: TextAlign.center),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: image.isPrimary
                          ? null
                          : () {
                              _setPrimaryImage(image);
                              Navigator.pop(dialogContext);
                            },
                      icon: const Icon(Icons.star_outline),
                      label: Text(
                        image.isPrimary ? 'Principal' : 'Hacer principal',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _editImageMetadata(image);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Datos'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _removeImage(image);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAllImages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Text(
                      'Imágenes (${_images.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    final image = _images[index];
                    return _ToolImageThumbnail(
                      image: image,
                      size: double.infinity,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openImage(image);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openQuillDescription() async {
    final result = await Navigator.of(context).push<QuillDescriptionResult>(
      MaterialPageRoute(
        builder: (_) => QuillDescriptionPage(
          initialPlainText: _descriptionPlain,
          initialDelta: _descriptionDelta,
        ),
      ),
    );

    if (result == null) return;
    setState(() {
      _descriptionPlain = result.plainText;
      _descriptionDelta = result.deltaJson;
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = optionForValue(
      _conditionOptions,
      _condition,
      fieldKey: 'condition',
    );
    final typeStyle = optionForValue(_typeOptions, _type, fieldKey: 'type');
    final selectedType = _typeOptions.any((option) => option.label == _type)
        ? _type
        : null;
    final selectedCondition =
        _conditionOptions.any((option) => option.label == _condition)
        ? _condition
        : null;
    final voltages = voltageOptionsFor(_voltage);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Editar artículo · QUILL V22'
              : 'Nuevo artículo · QUILL V22',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'GUARDAR',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
            children: [
              const SectionTitle('Información básica'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre*',
                  prefixIcon: Icon(Icons.handyman_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe el nombre'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('tool_type'),
                initialValue: selectedType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Tipo*',
                  prefixIcon: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: fieldOptionIconWidget(typeStyle, size: 24),
                  ),
                ),
                hint: const Text('Selecciona el tipo'),
                items: _typeOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.label,
                        child: Row(
                          children: [
                            fieldOptionIconWidget(option, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                option.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                selectedItemBuilder: (context) => _typeOptions
                    .map(
                      (option) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _type = value);
                },
                validator: (value) => value == null || value.isEmpty
                    ? 'Selecciona el tipo'
                    : null,
              ),
              if (_showVoltage) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('tool_voltage'),
                  initialValue: _voltage.isEmpty ? null : _voltage,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Tensión',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: VoltageBadge(voltage: _voltage),
                    ),
                  ),
                  hint: const Text('Selecciona la tensión'),
                  items: voltages
                      .map(
                        (voltage) => DropdownMenuItem<String>(
                          value: voltage,
                          child: Row(
                            children: [
                              VoltageBadge(voltage: voltage),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  voltage.isEmpty ? 'Sin especificar' : voltage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (context) => voltages
                      .map(
                        (voltage) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            voltage.isEmpty ? 'Sin especificar' : voltage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _voltage = value);
                  },
                ),
              ],
              const SizedBox(height: 12),
              DescriptionQuillCard(
                text: _descriptionPlain,
                deltaJson: _descriptionDelta,
                onTap: _openQuillDescription,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Código de barras',
                  prefixIcon: Icon(Icons.qr_code_scanner),
                ),
              ),
              const SizedBox(height: 22),
              const SectionTitle('Existencias'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(labelText: 'Unidad'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _minimumStock,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cantidad mínima',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 22),
              const SectionTitle('Estado'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedCondition,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Estado de la herramienta',
                  prefixIcon: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: fieldOptionIconWidget(style, size: 24),
                  ),
                ),
                items: _conditionOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.label,
                        child: Row(
                          children: [
                            fieldOptionIconWidget(option, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                option.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                selectedItemBuilder: (context) => _conditionOptions
                    .map(
                      (option) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _condition = value);
                },
              ),
              const SizedBox(height: 22),
              const SectionTitle('Compra e imagen'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _purchasePrice,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio de compra (€)',
                  prefixIcon: Icon(Icons.euro),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    _images.length == 1
                        ? '1 imagen'
                        : '${_images.length} imágenes',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6F747A),
                    ),
                  ),
                  const Spacer(),
                  if (_images.length > 4)
                    TextButton(
                      onPressed: _openAllImages,
                      child: Text('Ver todas (${_images.length})'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD7DDE3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CompactImageToolbar(
                      onCamera: () => _storePickedImage(ImageSource.camera),
                      onUrl: _downloadImageFromUrl,
                      onAi: _openAiImageOption,
                      onGallery: () => _storePickedImage(ImageSource.gallery),
                    ),
                    if (_images.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        child: Text(
                          'Sin imágenes. Puedes añadir tantas como necesites.',
                          style: TextStyle(
                            color: Color(0xFF7A7F85),
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 104,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final image = _images[index];
                            return _ToolImageThumbnail(
                              image: image,
                              size: 88,
                              onTap: () => _openImage(image),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar artículo'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF168BD2),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactImageToolbar extends StatelessWidget {
  const _CompactImageToolbar({
    required this.onCamera,
    required this.onUrl,
    required this.onAi,
    required this.onGallery,
  });

  final VoidCallback onCamera;
  final VoidCallback onUrl;
  final VoidCallback onAi;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      color: const Color(0xFFF0F1F2),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _CompactImageAction(
            icon: Icons.photo_camera,
            tooltip: 'Cámara',
            onTap: onCamera,
          ),
          _CompactImageAction(icon: Icons.link, tooltip: 'URL', onTap: onUrl),
          _CompactImageAction(
            icon: Icons.auto_awesome,
            tooltip: 'IA',
            onTap: onAi,
          ),
          _CompactImageAction(
            icon: Icons.photo_library_outlined,
            tooltip: 'Galería',
            onTap: onGallery,
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(right: 10, left: 4),
            child: Text(
              'IMÁGENES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7A7F85),
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactImageAction extends StatelessWidget {
  const _CompactImageAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      iconSize: 25,
      color: const Color(0xFF39444D),
      icon: Icon(icon),
    );
  }
}

class _ToolImageThumbnail extends StatelessWidget {
  const _ToolImageThumbnail({
    required this.image,
    required this.size,
    required this.onTap,
  });

  final ToolImage image;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final exists = File(image.path).existsSync();

    return SizedBox(
      width: size.isFinite ? size : null,
      height: size.isFinite ? size : null,
      child: Material(
        color: const Color(0xFFE9EDF0),
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: exists ? onTap : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (exists)
                Image.file(File(image.path), fit: BoxFit.cover)
              else
                const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF8A9096),
                  ),
                ),
              if (image.isPrimary)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.star,
                      size: 16,
                      color: Colors.amber,
                    ),
                  ),
                ),
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    image.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DescriptionQuillCard extends StatelessWidget {
  const DescriptionQuillCard({
    super.key,
    required this.text,
    required this.deltaJson,
    required this.onTap,
  });

  final String text;
  final String deltaJson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: false,
        decoration: const InputDecoration(
          labelText: 'Descripción',
          suffixIcon: Icon(Icons.edit_outlined, color: Color(0xFF168BD2)),
          contentPadding: EdgeInsets.fromLTRB(16, 18, 12, 16),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Align(
            alignment: Alignment.topLeft,
            child: hasText
                ? _RichDeltaPreview(plainText: text, deltaJson: deltaJson)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _RichDeltaPreview extends StatelessWidget {
  const _RichDeltaPreview({required this.plainText, required this.deltaJson});

  final String plainText;
  final String deltaJson;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];

    try {
      if (deltaJson.trim().isNotEmpty) {
        final decoded = jsonDecode(deltaJson);
        if (decoded is List) {
          for (final operation in decoded) {
            if (operation is! Map) continue;

            final insert = operation['insert'];
            if (insert is! String) continue;

            final rawAttributes = operation['attributes'];
            final attributes = rawAttributes is Map
                ? Map<String, dynamic>.from(rawAttributes)
                : const <String, dynamic>{};

            spans.add(
              TextSpan(text: insert, style: _styleFromAttributes(attributes)),
            );
          }
        }
      }
    } catch (_) {
      // Si un Delta antiguo no se puede interpretar, mostramos texto normal.
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: plainText));
    }

    return RichText(
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 15,
          height: 1.35,
          color: Color(0xFF2B3035),
        ),
        children: spans,
      ),
    );
  }

  TextStyle _styleFromAttributes(Map<String, dynamic> attributes) {
    final decorations = <TextDecoration>[];

    if (attributes['underline'] == true) {
      decorations.add(TextDecoration.underline);
    }
    if (attributes['strike'] == true) {
      decorations.add(TextDecoration.lineThrough);
    }

    return TextStyle(
      fontWeight: attributes['bold'] == true
          ? FontWeight.w700
          : FontWeight.normal,
      fontStyle: attributes['italic'] == true
          ? FontStyle.italic
          : FontStyle.normal,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      color: _parseColor(attributes['color']),
      backgroundColor: _parseColor(attributes['background']),
      fontSize: _parseFontSize(attributes['size']),
    );
  }

  Color? _parseColor(dynamic value) {
    if (value is! String || value.isEmpty) return null;

    var hex = value.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }

    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    if (hex.length != 8) return null;

    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  double? _parseFontSize(dynamic value) {
    if (value == null) return null;

    final text = value.toString();
    switch (text) {
      case 'small':
        return 12;
      case 'large':
        return 20;
      case 'huge':
        return 26;
      default:
        return double.tryParse(text);
    }
  }
}

class QuillDescriptionResult {
  const QuillDescriptionResult({
    required this.plainText,
    required this.deltaJson,
  });

  final String plainText;
  final String deltaJson;
}

class QuillDescriptionPage extends StatefulWidget {
  const QuillDescriptionPage({
    super.key,
    required this.initialPlainText,
    required this.initialDelta,
  });

  final String initialPlainText;
  final String initialDelta;

  @override
  State<QuillDescriptionPage> createState() => _QuillDescriptionPageState();
}

class _QuillDescriptionPageState extends State<QuillDescriptionPage> {
  late final QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    Document document;
    if (widget.initialDelta.trim().isNotEmpty) {
      try {
        document = Document.fromJson(
          jsonDecode(widget.initialDelta) as List<dynamic>,
        );
      } catch (_) {
        document = _documentFromPlain(widget.initialPlainText);
      }
    } else {
      document = _documentFromPlain(widget.initialPlainText);
    }

    _controller = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Document _documentFromPlain(String value) {
    final text = value.trim().isEmpty ? '\n' : '${value.trimRight()}\n';
    return Document.fromJson([
      {'insert': text},
    ]);
  }

  void _accept() {
    Navigator.of(context).pop(
      QuillDescriptionResult(
        plainText: _controller.document.toPlainText().trim(),
        deltaJson: jsonEncode(_controller.document.toDelta().toJson()),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Editor Quill',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _accept,
            child: const Text(
              'ACEPTAR',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3CD),
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Quill integrado en la aplicación, en pantalla propia.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            QuillSimpleToolbar(
              controller: _controller,
              config: const QuillSimpleToolbarConfig(),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFB0B7BE)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: QuillEditor.basic(
                  controller: _controller,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  config: const QuillEditorConfig(
                    placeholder: 'Escribe aquí…',
                    padding: EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF5E646A),
      ),
    );
  }
}

String formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}
