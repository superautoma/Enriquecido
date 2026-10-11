import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presentation only: the inventory owns navigation and all data operations.
class ToolsMainMenu extends StatelessWidget {
  const ToolsMainMenu({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: math.min(360, MediaQuery.sizeOf(context).width - 24),
      backgroundColor: const Color(0xFFFAFBFD),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: ListView(
          key: const ValueKey('tools_menu_scroll'),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Menú',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF20242A),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Gestor de Herramientas',
                    style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            for (var index = 0; index < _groups.length; index++) ...[
              if (index > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE4EAF0),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  _groups[index].title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              for (final option in _groups[index].options)
                _MenuOptionRow(
                  option: option,
                  tint: _groups[index].tint,
                  onTap: () => onSelected(option.value),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuOptionRow extends StatelessWidget {
  const _MenuOptionRow({
    required this.option,
    required this.tint,
    required this.onTap,
  });

  final _MenuOption option;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        key: ValueKey('menu_${option.value}'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minVerticalPadding: 12,
        horizontalTitleGap: 12,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(option.icon, size: 22, color: const Color(0xFF34617B)),
        ),
        title: Text(
          option.label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF273444),
          ),
        ),
        trailing: option.opensPage
            ? const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _MenuOption {
  const _MenuOption(this.value, this.label, this.icon, {this.opensPage = true});
  final String value;
  final String label;
  final IconData icon;
  final bool opensPage;
}

class _MenuGroup {
  const _MenuGroup(this.title, this.tint, this.options);
  final String title;
  final Color tint;
  final List<_MenuOption> options;
}

const _groups = [
  _MenuGroup('TRABAJO DIARIO', Color(0xFFEAF4FE), [
    _MenuOption(
      'inventory',
      'Herramientas',
      Icons.home_repair_service_outlined,
      opensPage: false,
    ),
    _MenuOption('loans', 'Préstamos', Icons.handshake_outlined),
    _MenuOption('maintenance', 'Mantenimientos', Icons.build_outlined),
    _MenuOption('trash', 'Papelera', Icons.delete_outline),
    _MenuOption(
      'management',
      'Gestión de herramientas',
      Icons.dashboard_outlined,
    ),
  ]),
  _MenuGroup('IA Y CUENTA', Color(0xFFF0EDFA), [
    _MenuOption('ai_photo', 'Crear ficha con IA', Icons.auto_awesome_outlined),
    _MenuOption(
      'ai_settings',
      'Conexión con ChatGPT',
      Icons.manage_accounts_outlined,
    ),
  ]),
  _MenuGroup('CONFIGURACIÓN', Color(0xFFEDF5F2), [
    _MenuOption('fields', 'Tipos y estados', Icons.tune_outlined),
    _MenuOption('icons', 'Gestor de iconos', Icons.image_outlined),
    _MenuOption('security', 'Seguridad y acceso', Icons.lock_outline),
    _MenuOption(
      'button_feedback',
      'Sonido y vibración',
      Icons.touch_app_outlined,
    ),
  ]),
  _MenuGroup('DATOS', Color(0xFFFBF2E7), [
    _MenuOption(
      'backup',
      'Copia de seguridad',
      Icons.backup_outlined,
      opensPage: false,
    ),
    _MenuOption('import', 'Importar datos', Icons.playlist_add_outlined),
    _MenuOption('database', 'Base de datos', Icons.storage_outlined),
    _MenuOption(
      'restore',
      'Restaurar y sustituir',
      Icons.restore_rounded,
      opensPage: false,
    ),
  ]),
];
