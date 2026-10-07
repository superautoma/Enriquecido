#!/usr/bin/env python3
"""Create a synthetic format-2 backup for Gestor de Herramientas v80.

Uses the production SQL declarations; never opens a user's database.
Run: python3 scripts/create_demo_inventory.py --output /tmp/100_herramientas.zip
"""
import argparse
import calendar
from datetime import date, datetime, timedelta
import json
from pathlib import Path
import re
import sqlite3
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANUAL = [
    'Martillo de carpintero', 'Martillo de bola', 'Maza de goma',
    'Destornillador plano 6 mm', 'Destornillador Phillips PH2',
    'Destornillador Pozidriv PZ2', 'Llave ajustable 250 mm',
    'Llave de grifa 350 mm', 'Sierra de arco', 'Serrucho de costilla',
    'Formón de 20 mm', 'Cepillo de carpintero', 'Lima plana',
    'Sargento de apriete 300 mm', 'Tornillo de banco', 'Escuadra metálica',
    'Gato rápido 150 mm', 'Flexómetro de 5 m', 'Nivel de burbuja',
    'Alicates universales', 'Tijeras de electricista', 'Alicates de corte',
    'Alicates de punta larga', 'Pelacables automático', 'Llave fija 13 mm',
    'Llave de carraca', 'Llave dinamométrica', 'Remachadora manual',
    'Cúter profesional', 'Grapadora manual',
]
ELECTRIC = [
    ('Taladro percutor', '230 V'), ('Taladro atornillador', '18 V'),
    ('Martillo perforador', '230 V'), ('Atornillador de impacto', '18 V'),
    ('Sierra de calar', '230 V'), ('Sierra circular', '18 V'),
    ('Sierra de sable', '18 V'), ('Amoladora angular 125 mm', '230 V'),
    ('Lijadora orbital', '230 V'), ('Lijadora de banda', '230 V'),
    ('Fresadora de superficie', '230 V'), ('Cepillo eléctrico', '230 V'),
    ('Pistola de aire caliente', '230 V'), ('Multiherramienta oscilante', '18 V'),
    ('Soldador de estaño', '230 V'), ('Estación de soldadura', '230 V'),
    ('Compresor portátil', '230 V'), ('Aspirador de taller', '230 V'),
    ('Sierra ingletadora', '230 V'), ('Esmeriladora de banco', '230 V'),
    ('Linterna de trabajo', '12 V'), ('Pistola de silicona', '230 V'),
    ('Cortadora de azulejos eléctrica', '230 V'), ('Pulidora', '230 V'),
    ('Taladro de columna', '400 V'),
]
SPARES = [
    'Batería de 18 V y 4 Ah', 'Batería de 12 V y 2 Ah', 'Cargador de 18 V',
    'Cargador de 12 V', 'Portabrocas de 13 mm', 'Escobillas de motor',
    'Correa para lijadora', 'Cable de alimentación', 'Interruptor de taladro',
    'Plato de lijadora 125 mm', 'Filtro de aspirador', 'Manguera de aspiración',
    'Guía paralela de sierra', 'Protector de amoladora', 'Mandril SDS Plus',
]
CONSUMABLES = [
    'Broca para metal 3 mm', 'Broca para metal 5 mm', 'Broca para metal 8 mm',
    'Broca para madera 6 mm', 'Broca para pared 8 mm', 'Punta Phillips PH2',
    'Punta Torx T20', 'Disco de corte 125 mm', 'Disco de desbaste 125 mm',
    'Hoja de sierra de calar', 'Lija de grano 80', 'Lija de grano 120',
    'Lija de grano 240', 'Remaches de 4 mm', 'Grapas de 10 mm',
    'Tornillos para madera 4 x 40', 'Tacos de pared de 8 mm',
    'Cable eléctrico de prueba', 'Cinta aislante', 'Barras de silicona',
]
KITS = [
    ('Juego de destornilladores', ['Plano 3 mm', 'Plano 6 mm', 'Phillips PH1', 'Phillips PH2']),
    ('Juego de llaves Allen', ['Allen 3 mm', 'Allen 4 mm', 'Allen 5 mm', 'Allen 6 mm']),
    ('Juego de llaves Torx', ['Torx T10', 'Torx T15', 'Torx T20', 'Torx T25']),
    ('Maletín de vasos y carraca', ['Carraca de 1/2', 'Vaso de 10 mm', 'Vaso de 13 mm', 'Prolongador de 125 mm']),
    ('Maletín de taladro a batería', ['Taladro de 18 V', 'Batería de 18 V', 'Cargador de 18 V', 'Portapuntas']),
    ('Maletín de medición', ['Multímetro', 'Pinza amperimétrica', 'Comprobador de tensión', 'Puntas de prueba']),
    ('Maletín de fontanería', ['Cortatubos', 'Llave de grifa', 'Escariador', 'Llave de lavabo']),
    ('Maletín de carpintería', ['Formón de 10 mm', 'Formón de 20 mm', 'Mazo de madera', 'Escuadra']),
    ('Juego de alicates', ['Universal', 'Corte diagonal', 'Punta larga', 'Boca curva']),
    ('Maletín de crimpado', ['Crimpadora', 'Pelacables', 'Cortacables', 'Comprobador de cable']),
]


def iso(day):
    return day.isoformat() + 'T00:00:00.000'


def insert(db, table, **values):
    columns = ','.join(values)
    slots = ','.join('?' for _ in values)
    return db.execute(f'INSERT INTO {table} ({columns}) VALUES ({slots})',
                      list(values.values())).lastrowid


def create_schema(db):
    main = (ROOT / 'flutter/lib/main_quill_integrated_test.dart').read_text()
    management = (ROOT / 'flutter/lib/tool_management.dart').read_text()
    # Keep exactly the table definitions used by the current application.
    for source in (main, management):
        for literal in re.findall(r"'''(.*?)'''", source, re.S):
            sql = literal.strip()
            if sql.startswith('CREATE TABLE'):
                db.execute(sql)
    for table, columns in {
        'tools': {
            'parent_id': 'INTEGER REFERENCES tools(id) ON DELETE RESTRICT',
            'is_set': 'INTEGER NOT NULL DEFAULT 0',
            'out_of_service': 'INTEGER NOT NULL DEFAULT 0',
            'service_notes': "TEXT NOT NULL DEFAULT ''",
        },
        'tool_loans': {
            'returned_quantity': 'REAL NOT NULL DEFAULT 0',
            'contact': "TEXT NOT NULL DEFAULT ''",
            'delivery_condition': "TEXT NOT NULL DEFAULT ''",
            'accessories': "TEXT NOT NULL DEFAULT ''",
            'reminder_days': 'INTEGER NOT NULL DEFAULT 1',
        },
    }.items():
        for name, declaration in columns.items():
            db.execute(f'ALTER TABLE {table} ADD COLUMN {name} {declaration}')
    for sql in [
        'CREATE INDEX idx_tool_images_tool_id ON tool_images(tool_id)',
        'CREATE INDEX idx_field_options_key_position ON field_options(field_key, position)',
        'CREATE INDEX idx_tool_loans_active ON tool_loans(tool_id, returned_on)',
        'CREATE INDEX idx_tools_parent ON tools(parent_id)',
    ]:
        db.execute(sql)
    db.execute('PRAGMA user_version=9')
    types = [('Herramienta manual', 'handyman', 0xFF1976D2),
             ('Herramienta eléctrica', 'electrical', 0xFFF9A825),
             ('Repuesto', 'settings', 0xFF7E57C2), ('Consumible', 'inventory', 0xFF00897B)]
    conditions = [('Bueno', 'check', 0xFF43A047), ('Revisar', 'build', 0xFFF9A825),
                  ('Averiado', 'error', 0xFFE53935), ('Prestado', 'swap', 0xFF7E57C2)]
    for key, options in [('type', types), ('condition', conditions)]:
        for position, (label, icon, color) in enumerate(options):
            insert(db, 'field_options', field_key=key, label=label, icon_key=icon,
                   color_value=color, position=position)
    insert(db, 'management_settings', key='notifications', value='0')


def populate_tools(db):
    def tool(tool_id, name, kind, quantity=1, voltage='', parent=None, is_set=False):
        description = ('Ficha ficticia para probar la aplicación. Datos de ejemplo; '
                       'precios y características no corresponden a un fabricante real.\n'
                       f'Referencia PRUEBA-{tool_id:03d}. ' +
                       ('Contiene cuatro piezas con fichas independientes.' if is_set else
                        'Puedes modificarla, prestarla y adjuntar documentos.'))
        insert(db, 'tools', id=tool_id, name='[PRUEBA] ' + name,
               description=description,
               description_delta=json.dumps([{'insert': description + '\n'}], ensure_ascii=False),
               barcode=f'PRUEBA-{tool_id:03d}', quantity=quantity,
               unit='m' if tool_id == 88 else 'ud',
               minimum_stock=5 if kind in ('Repuesto', 'Consumible') else 0,
               purchase_price=round(2.5 + tool_id * 1.17, 2), tool_type=kind,
               voltage=voltage, parent_id=parent, is_set=int(is_set))
    manual_quantities = {14: 12, 17: 4, 20: 3, 21: 2, 25: 2}
    for i, name in enumerate(MANUAL, 1):
        tool(i, name, 'Herramienta manual', manual_quantities.get(i, 1))
    for i, (name, voltage) in enumerate(ELECTRIC, 31):
        tool(i, name, 'Herramienta eléctrica', 3 if i == 51 else 1, voltage)
    for i, name in enumerate(SPARES, 56):
        tool(i, name, 'Repuesto', 2 + i % 7)
    for i, name in enumerate(CONSUMABLES, 71):
        quantity = 0 if i in (79, 82, 88, 90) else (i % 5 + 1) * 10
        if i in (71, 72, 85):
            quantity = 2
        if i == 88:
            quantity = 12.5
        tool(i, name, 'Consumible', quantity)
    for i, (name, pieces) in enumerate(KITS, 91):
        tool(i, name, 'Herramienta manual', is_set=True)
        for offset, piece in enumerate(pieces):
            component_id = 101 + (i - 91) * 4 + offset
            electric = i == 95 and offset < 3
            tool(component_id, piece + ' · ' + name,
                 'Herramienta eléctrica' if electric else 'Herramienta manual',
                 voltage=('230 V' if offset == 2 else '18 V') if electric else '', parent=i)
    for tool_id, reason in [(9, 'Hoja pendiente de sustitución'),
                            (35, 'Revisar interruptor'), (41, 'Revisión del cable'),
                            (64, 'Interruptor defectuoso'), (99, 'Revisar el conjunto'),
                            (139, 'Corte irregular; revisar antes de usar')]:
        db.execute('UPDATE tools SET out_of_service=1, condition=?, service_notes=? WHERE id=?',
                   ('Averiado' if tool_id in (35, 64) else 'Revisar',
                    '[PRUEBA] ' + reason, tool_id))


def populate_loans(db, today):
    people = ['Ana Demo', 'Luis Demo', 'Marta Demo', 'Carlos Demo', 'Lucía Demo', 'Pablo Demo']
    for index, name in enumerate(people, 1):
        insert(db, 'borrowers', name=name, contact=f'persona{index}@example.invalid')

    def loan(tool_id, person, quantity=1, start=-7, due=7, returned=None,
             returned_quantity=0, contents=None, accessories='Funda de transporte de prueba'):
        tool = db.execute('SELECT * FROM tools WHERE id=?', (tool_id,)).fetchone()
        start_day = today + timedelta(days=start)
        due_day = today + timedelta(days=due) if due is not None else None
        returned_day = today + timedelta(days=returned) if returned is not None else None
        name = people[person % len(people)]
        loan_id = insert(db, 'tool_loans', tool_id=tool_id, tool_name=tool['name'],
                         borrower=name, started_on=iso(start_day),
                         due_on=iso(due_day) if due_day else None,
                         returned_on=iso(returned_day) if returned_day else None,
                         notes='[PRUEBA] Puedes editar estas observaciones y la fecha prevista.',
                         previous_condition='Bueno', quantity=quantity, unit=tool['unit'],
                         returned_quantity=quantity if returned_day else returned_quantity,
                         contact=f'persona{person % len(people) + 1}@example.invalid',
                         delivery_condition='Limpia y comprobada (dato ficticio)',
                         accessories=accessories, reminder_days=1)
        delivery_quantity = quantity
        if contents is not None:
            delivery_quantity = 0
            for component_id, amount, returned_amount in contents:
                component = db.execute('SELECT name FROM tools WHERE id=?', (component_id,)).fetchone()
                insert(db, 'loan_contents', loan_id=loan_id, component_id=component_id,
                       name=component['name'], quantity=amount, returned_quantity=returned_amount)
                delivery_quantity += amount
        insert(db, 'loan_events', loan_id=loan_id, kind='Entrega', created_at=iso(start_day),
               performed_on=iso(start_day), quantity=delivery_quantity,
               condition='Bueno', notes='Entrega ficticia para pruebas.', details=accessories)
        if returned_day or returned_quantity or (contents and any(c[2] for c in contents)):
            when = returned_day or today - timedelta(days=1)
            returned_amount = (delivery_quantity if returned_day else
                               sum(c[2] for c in contents) if contents else returned_quantity)
            details = '\n'.join(f'{c[0]}: {c[2]}' for c in contents if c[2]) if contents else ''
            insert(db, 'loan_events', loan_id=loan_id, kind='Devolución', created_at=iso(when),
                   performed_on=iso(when), quantity=returned_amount,
                   condition='Bueno', notes='Devolución ficticia: total o parcial.', details=details)
        if returned_day is None:
            db.execute("UPDATE tools SET condition='Prestado' WHERE id=?", (tool_id,))
        return loan_id

    # Six closed loans, including a complete kit, remain editable in history.
    for index, tool_id in enumerate([1, 4, 7, 34, 38]):
        loan(tool_id, index, start=-25 - index, due=-10, returned=-12 + index)
    loan(94, 5, start=-30, due=-12, returned=-14,
         contents=[(i, 1, 1) for i in range(113, 117)])
    # Ten open loans: three overdue, stock shared by two people, partial returns,
    # no planned date, a complete kit and a selection of kit pieces.
    loan(2, 0, start=-12, due=-3)
    loan(31, 1, start=-10, due=-1)
    loan(14, 2, quantity=5, returned_quantity=2, start=-8, due=-2)
    loan(14, 3, quantity=3, start=-4, due=5)
    loan(17, 4, quantity=2, returned_quantity=1, start=-6, due=10)
    loan(32, 5, start=-3, due=14)
    loan(51, 0, quantity=1, start=-2, due=None)
    loan(88, 1, quantity=3.5, returned_quantity=1, start=-5, due=4, accessories='')
    full_kit = loan(91, 2, start=-7, due=8,
                    contents=[(i, 1, 0) for i in range(101, 105)])
    partial_kit = loan(92, 3, quantity=0, start=-9, due=3,
                       contents=[(105, 1, 1), (106, 1, 0)])
    insert(db, 'loan_events', loan_id=partial_kit, kind='Modificación',
           created_at=iso(today), notes='[PRUEBA] Se ha ampliado el plazo de devolución.',
           details='Plazo: ampliado 3 días. Observaciones anteriores: devolver el juego completo.')
    return full_kit, partial_kit


def add_months(day, months):
    total = day.year * 12 + day.month - 1 + months
    year, month = total // 12, total % 12 + 1
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def populate_maintenance(db, today):
    tool_ids = [9, 35, 41, 64, 99, 139, 31, 32, 33, 38,
                39, 40, 43, 45, 47, 48, 50, 55, 95, 96]
    for index, tool_id in enumerate(tool_ids):
        one_off = index < 6
        interval = 0 if one_off else 30 if index % 3 == 0 else 6
        unit = 'días' if interval == 30 else 'meses'
        due = today + timedelta(days=(-4 + index if one_off else 5 + index * 2))
        completed = index >= 12
        previous = today - timedelta(days=60 - index)
        if completed and interval:
            due = previous + timedelta(days=interval) if unit == 'días' else add_months(previous, interval)
        task_id = insert(db, 'maintenance_tasks', tool_id=tool_id,
                         title='[PRUEBA] ' + ('Reparación pendiente' if one_off else 'Revisión periódica'),
                         due_on=iso(due), interval_value=interval, interval_unit=unit,
                         notes='Plan ficticio para probar fechas, avisos e historial. '
                               'Consulta el manual real para definir el mantenimiento.',
                         reminder_days=2, enabled=1)
        if completed:
            insert(db, 'maintenance_records', task_id=task_id, performed_on=iso(previous),
                   notes='[PRUEBA] Limpieza y comprobación registradas como ejemplo.',
                   parts='Repuesto ficticio' if index % 2 else '', cost=round(index * 1.75, 2))
    # A completed one-off task shows the disabled/finished case.
    finished = insert(db, 'maintenance_tasks', tool_id=1, title='[PRUEBA] Sustitución de mango completada',
                      due_on=iso(today - timedelta(days=20)), interval_value=0,
                      interval_unit='meses', notes='Intervención ficticia terminada.', enabled=0)
    insert(db, 'maintenance_records', task_id=finished, performed_on=iso(today - timedelta(days=20)),
           notes='[PRUEBA] Mango sustituido.', parts='Mango de prueba', cost=7.5)


def populate_documents(db, directory, today, loan_ids):
    directory.mkdir()
    for index, tool_id in enumerate([31, 32, 35, 38, 41, 47, 48, 55, 91, 92, 94, 95], 1):
        name = db.execute('SELECT name FROM tools WHERE id=?', (tool_id,)).fetchone()[0]
        filename = f'prueba_manual_{tool_id:03d}.txt'
        (directory / filename).write_text(
            f'DOCUMENTO DE PRUEBA\n{name}\nFecha: {today:%d/%m/%Y}\n\n'
            'Este archivo es ficticio y sirve para probar abrir, compartir, renombrar '
            'y sustituir documentos. No contiene instrucciones de uso ni de seguridad.\n'
            'Sustitúyelo por el manual real del fabricante para uso habitual.\n', encoding='utf-8')
        insert(db, 'tool_documents', tool_id=tool_id, name='[PRUEBA] Manual de ejemplo (texto)',
               kind='Manual', file_name=filename)
    for tool_id, loan_id in zip([91, 92], loan_ids):
        filename = f'prueba_entrega_{tool_id}.txt'
        (directory / filename).write_text(
            'ENTREGA FICTICIA PARA PRUEBAS\n'
            'Documento asociado al préstamo. Puedes añadir fotos o cambiar este archivo.\n', encoding='utf-8')
        insert(db, 'tool_documents', tool_id=tool_id, loan_id=loan_id,
               name='[PRUEBA] Comprobante de entrega', kind='Entrega', file_name=filename)
    for task_id in [1, 2, 19, 20]:
        tool_id = db.execute('SELECT tool_id FROM maintenance_tasks WHERE id=?', (task_id,)).fetchone()[0]
        filename = f'prueba_mantenimiento_{task_id}.txt'
        (directory / filename).write_text(
            'DOCUMENTO DE MANTENIMIENTO FICTICIO\n'
            'Archivo para comprobar la asociación con una tarea. No es un procedimiento real.\n', encoding='utf-8')
        insert(db, 'tool_documents', tool_id=tool_id, task_id=task_id,
               name='[PRUEBA] Documento de revisión', kind='Mantenimiento', file_name=filename)


def validate(db, work):
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    assert not db.execute('PRAGMA foreign_key_check').fetchall()
    assert db.execute('PRAGMA user_version').fetchone()[0] == 9
    assert db.execute('SELECT count(*) FROM tools WHERE parent_id IS NULL').fetchone()[0] == 100
    assert db.execute('SELECT count(*) FROM tools WHERE parent_id IS NOT NULL').fetchone()[0] == 40
    assert db.execute('SELECT count(*) FROM tools WHERE is_set=1').fetchone()[0] == 10
    assert db.execute('SELECT count(*) FROM tool_loans WHERE returned_on IS NULL').fetchone()[0] == 10
    assert db.execute('SELECT count(*) FROM tool_loans WHERE returned_on IS NOT NULL').fetchone()[0] == 6
    assert not db.execute('SELECT id FROM tool_loans WHERE returned_quantity<0 OR returned_quantity>quantity').fetchall()
    assert not db.execute('SELECT id FROM loan_contents WHERE returned_quantity<0 OR returned_quantity>quantity').fetchall()
    for tool in db.execute('SELECT * FROM tools'):
        assert json.loads(tool['description_delta'])[-1]['insert'].endswith('\n')
        own = db.execute('SELECT COALESCE(sum(quantity-returned_quantity),0) FROM tool_loans '
                         'WHERE tool_id=? AND returned_on IS NULL', (tool['id'],)).fetchone()[0]
        inherited = db.execute('SELECT COALESCE(sum(c.quantity-c.returned_quantity),0) '
                               'FROM loan_contents c JOIN tool_loans l ON l.id=c.loan_id '
                               'WHERE c.component_id=? AND l.returned_on IS NULL', (tool['id'],)).fetchone()[0]
        assert 0 <= own + inherited <= tool['quantity'], (tool['id'], own, inherited)
    for row in db.execute('SELECT * FROM tool_documents'):
        assert (work / 'tool_documents' / row['file_name']).is_file()
    for row in db.execute('SELECT * FROM tool_loans'):
        assert row['due_on'] is None or row['due_on'] >= row['started_on']
        assert row['returned_on'] is None or row['returned_on'] >= row['started_on']
    return {table: db.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
            for table in ['tools', 'tool_loans', 'loan_contents', 'loan_events',
                          'borrowers', 'maintenance_tasks', 'maintenance_records', 'tool_documents']}


def create_backup(output, today):
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tools_demo_') as temporary:
        work = Path(temporary)
        (work / 'database').mkdir()
        (work / 'tool_images').mkdir()
        db_path = work / 'database/gestor_herramientas.db'
        db = sqlite3.connect(db_path)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        create_schema(db)
        populate_tools(db)
        loan_ids = populate_loans(db, today)
        populate_maintenance(db, today)
        populate_documents(db, work / 'tool_documents', today, loan_ids)
        db.commit()
        counts = validate(db, work)
        db.close()
        manifest = {'format': 'gestor_herramientas_backup', 'format_version': 2,
                    'created_at': datetime.combine(today, datetime.min.time()).isoformat(),
                    'database': 'database/gestor_herramientas.db', 'images': 'tool_images',
                    'documents': 'tool_documents', 'note': 'Inventario ficticio para pruebas.',
                    'demo': True, 'demo_reference_date': today.isoformat(), 'demo_counts': counts}
        (work / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
        (work / 'LEEME.txt').write_text(
            '100 HERRAMIENTAS DE PRUEBA - GESTOR DE HERRAMIENTAS\n\n'
            'Compatible con Base Integral v80 (base de datos versión 9).\n'
            'Todos los registros son ficticios y se identifican con [PRUEBA].\n\n'
            'CÓMO CARGAR\n'
            '1. Guarda una copia de tus datos actuales desde el menú de la aplicación.\n'
            '2. Descarga este ZIP en el teléfono, sin descomprimirlo.\n'
            '3. En la aplicación, menú > Restaurar copia > selecciona este ZIP.\n'
            '4. Confirma la restauración. Sustituye toda la base actual, documentos e imágenes.\n'
            '5. Para recuperar tus datos, restaura la copia que guardaste en el paso 1.\n\n'
            'CONTENIDO\n'
            '100 fichas principales: 30 manuales, 25 eléctricas, 15 repuestos, '
            '20 consumibles y 10 conjuntos.\n'
            '40 piezas dentro de los conjuntos, que no duplican el listado principal.\n'
            '16 préstamos: 10 activos y 6 devueltos, con 3 plazos vencidos, '
            'devoluciones parciales, varios prestatarios y piezas de conjuntos.\n'
            '21 tareas de mantenimiento, 9 intervenciones y 6 fichas fuera de servicio.\n'
            '18 documentos de texto ficticios: manuales, entregas y mantenimiento. '
            'El móvil necesita una aplicación compatible para abrir archivos de texto.\n'
            'Cantidades variadas, existencias agotadas, mínimos, precios de ejemplo '
            'y referencias PRUEBA-001 a PRUEBA-140.\n'
            f'Fechas de referencia: {today:%d/%m/%Y}.\n'
            'Los avisos del teléfono están desactivados; puedes activarlos en Gestión de herramientas.\n\n'
            'CASOS PARA PROBAR\n'
            'Busca Sargento: hay dos préstamos simultáneos y una devolución parcial.\n'
            'Busca Cable eléctrico: cantidad decimal y devolución parcial.\n'
            'Busca Juego de destornilladores: conjunto completo prestado.\n'
            'Busca Juego de llaves Allen: préstamo de piezas, una ya devuelta.\n'
            'Busca Sierra de calar: herramienta averiada y fuera de servicio.\n'
            'Busca Maletín de crimpado: una de sus piezas está fuera de servicio.\n'
            'Abre Taladro percutor para probar préstamo vencido, documento y mantenimiento.\n',
            encoding='utf-8')
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(work.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(work).as_posix())
                elif path.name in ('tool_images', 'tool_documents'):
                    archive.writestr(path.relative_to(work).as_posix() + '/', b'')
        with zipfile.ZipFile(output) as archive:
            assert archive.testzip() is None
            assert 'database/gestor_herramientas.db' in archive.namelist()
        return counts


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--date', type=date.fromisoformat, default=date.today())
    args = parser.parse_args()
    result = create_backup(args.output, args.date)
    print(json.dumps({'output': str(Path(args.output).resolve()), 'counts': result}, ensure_ascii=False))
