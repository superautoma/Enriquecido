/// Offline photographic similarity, not semantic object identification.
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class VisualDescriptor {
  VisualDescriptor(this.edges, this.structure);
  final List<double> edges, structure;

  static VisualDescriptor? fromRgba(Uint8List pixels, int size) {
    final gray = List<double>.generate(
      size * size,
      (i) =>
          (.299 * pixels[i * 4] +
              .587 * pixels[i * 4 + 1] +
              .114 * pixels[i * 4 + 2]) /
          255,
    );
    final histogram = List<double>.filled(4 * 4 * 9, 0);
    double energy = 0;
    for (var y = 1; y < size - 1; y++) {
      for (var x = 1; x < size - 1; x++) {
        final dx = gray[y * size + x + 1] - gray[y * size + x - 1];
        final dy = gray[(y + 1) * size + x] - gray[(y - 1) * size + x];
        final magnitude = math.sqrt(dx * dx + dy * dy);
        energy += magnitude;
        final angle = (math.atan2(dy, dx) + math.pi) % math.pi;
        final bin = angle / math.pi * 9;
        final lower = bin.floor() % 9;
        final cell = ((y * 4 ~/ size) * 4 + x * 4 ~/ size) * 9;
        histogram[cell + lower] += magnitude * (1 - (bin - bin.floor()));
        histogram[cell + (lower + 1) % 9] += magnitude * (bin - bin.floor());
      }
    }
    // Uniform images cannot meaningfully describe a tool.
    if (energy / (size * size) < .005) return null;
    final structure = List<double>.filled(16 * 16, 0);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        structure[(y * 16 ~/ size) * 16 + x * 16 ~/ size] += gray[y * size + x];
      }
    }
    final mean = structure.reduce((a, b) => a + b) / structure.length;
    for (var i = 0; i < structure.length; i++) {
      structure[i] -= mean;
    }
    return VisualDescriptor(_normalize(histogram), _normalize(structure));
  }

  static List<double> _normalize(List<double> values) {
    final norm = math.sqrt(values.fold<double>(0, (s, v) => s + v * v));
    return values.map((v) => norm == 0 ? 0.0 : v / norm).toList();
  }

  double similarity(VisualDescriptor other) {
    double dot(List<double> a, List<double> b) => List<double>.generate(
      a.length,
      (i) => a[i] * b[i],
    ).fold(0.0, (s, v) => s + v);
    return (.75 * dot(edges, other.edges) +
            .25 * math.max(0, dot(structure, other.structure)))
        .clamp(0.0, 1.0);
  }
}

class VisualCandidate {
  const VisualCandidate(this.id, this.paths);
  final int id;
  final List<String> paths;
}

class VisualMatch {
  const VisualMatch(this.id, this.score, this.path);
  final int id;
  final double score;
  final String path;
}

class VisualSearchReport {
  const VisualSearchReport(
    this.matches,
    this.comparablePhotos,
    this.skippedPhotos,
  );
  final List<VisualMatch> matches;
  final int comparablePhotos, skippedPhotos;
  // Conservative heuristic, deliberately not a calibrated confidence probability.
  bool get hasCloseMatch => matches.isNotEmpty && matches.first.score >= .90;
}

class LocalVisualSearch {
  final _cache = LinkedHashMap<String, VisualDescriptor?>();
  int get cachedDescriptors => _cache.length;
  void clear() => _cache.clear();

  Future<VisualDescriptor?> describe(String path) async {
    final file = File(path);
    FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException {
      return null;
    }
    if (stat.type != FileSystemEntityType.file || stat.size > 16 * 1024 * 1024)
      return null;
    final key = '$path:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    if (_cache.containsKey(key)) {
      final value = _cache.remove(key);
      _cache[key] = value;
      return value;
    }
    VisualDescriptor? descriptor;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? imageDescriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(path);
      imageDescriptor = await ui.ImageDescriptor.encoded(buffer);
      // Limit decoded pixels; reject extreme files before native decoding.
      if (imageDescriptor.width * imageDescriptor.height > 50000000)
        return null;
      codec = await imageDescriptor.instantiateCodec(
        targetWidth: 128,
        targetHeight: 128,
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null)
        descriptor = VisualDescriptor.fromRgba(data.buffer.asUint8List(), 128);
    } catch (_) {
      // Missing/corrupt/unsupported photographs are skipped, never modified.
    } finally {
      image?.dispose();
      codec?.dispose();
      imageDescriptor?.dispose();
      buffer?.dispose();
    }
    _cache[key] = descriptor;
    while (_cache.length > 256) {
      _cache.remove(_cache.keys.first);
    }
    return descriptor;
  }

  Future<VisualSearchReport> search(
    String query,
    List<VisualCandidate> candidates, {
    bool Function()? cancelled,
  }) async {
    final descriptor = await describe(query);
    if (descriptor == null)
      throw const FormatException(
        'Imagen ilegible o sin detalle visual suficiente.',
      );
    final matches = <VisualMatch>[];
    var comparable = 0, skipped = 0;
    for (final candidate in candidates) {
      VisualMatch? best;
      for (final path in candidate.paths.toSet()) {
        if (cancelled?.call() ?? false)
          return VisualSearchReport(matches, comparable, skipped);
        final other = await describe(path);
        if (other == null) {
          skipped++;
          continue;
        }
        comparable++;
        final match = VisualMatch(
          candidate.id,
          descriptor.similarity(other),
          path,
        );
        if (best == null || match.score > best.score) best = match;
        // Give Flutter a chance to paint between photographs.
        await Future<void>.delayed(Duration.zero);
      }
      if (best != null) matches.add(best);
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return VisualSearchReport(matches, comparable, skipped);
  }
}

Future<XFile?> pickVisualQuery(ImageSource source, {ImagePicker? picker}) =>
    (picker ?? ImagePicker()).pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
      requestFullMetadata: false,
    );

String visualPickerError(Object error) {
  if (error is PlatformException &&
      (error.code.toLowerCase().contains('denied') ||
          error.code.toLowerCase().contains('restricted'))) {
    return 'Permiso denegado. Permite el acceso a la cámara o a las fotos en Ajustes para continuar.';
  }
  return 'No se pudo abrir o comparar la imagen. Puedes volver a intentarlo.';
}
