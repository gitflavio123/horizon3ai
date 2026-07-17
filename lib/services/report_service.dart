import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Genera ed esporta report (PDF e CSV) dei risultati di un pentest.
/// Funziona su web (download del file) e desktop/mobile (dialog di share/salvataggio).
class ReportService {
  static const PdfColor _critical = PdfColor.fromInt(0xFFD32F2F);
  static const PdfColor _high = PdfColor.fromInt(0xFFFF5252);
  static const PdfColor _medium = PdfColor.fromInt(0xFFF57C00);
  static const PdfColor _low = PdfColor.fromInt(0xFF607D8B);
  static const PdfColor _accent = PdfColor.fromInt(0xFF00838F);
  static const PdfColor _dark = PdfColor.fromInt(0xFF141724);

  PdfColor _severityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return _critical;
      case 'HIGH':
        return _high;
      case 'MEDIUM':
        return _medium;
      default:
        return _low;
    }
  }

  int _severityRank(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return 0;
      case 'HIGH':
        return 1;
      case 'MEDIUM':
        return 2;
      default:
        return 3;
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'N/D';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return cleaned.isEmpty ? 'pentest' : cleaned;
  }

  List<Map<String, dynamic>> _sortedWeaknesses(List<Map<String, dynamic>> weaknesses) {
    final sorted = List<Map<String, dynamic>>.from(weaknesses);
    sorted.sort((a, b) => _severityRank(a['severity']?.toString() ?? '')
        .compareTo(_severityRank(b['severity']?.toString() ?? '')));
    return sorted;
  }

  Map<String, int> _severityCounts(List<Map<String, dynamic>> weaknesses) {
    final counts = <String, int>{'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0};
    for (final w in weaknesses) {
      final sev = (w['severity']?.toString() ?? 'LOW').toUpperCase();
      counts.update(counts.containsKey(sev) ? sev : 'LOW', (v) => v + 1);
    }
    return counts;
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  Future<void> exportPdf({
    required Map<String, dynamic> detail,
    required List<Map<String, dynamic>> weaknesses,
  }) async {
    final doc = pw.Document();

    final name = detail['name']?.toString() ?? 'Operazione senza nome';
    final opId = detail['op_id']?.toString() ?? 'N/D';
    final state = detail['state']?.toString() ?? 'N/D';
    final type = detail['op_type']?.toString() ?? 'N/D';
    final weaknessCount = detail['weaknesses_count'] as int? ?? weaknesses.length;
    final credentials = detail['credentials_count'] as int? ?? 0;
    final credAccess = detail['cred_access_count'] as int? ?? 0;
    final generatedAt = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    final counts = _severityCounts(weaknesses);
    final sorted = _sortedWeaknesses(weaknesses);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Horizon3.ai NodeZero - Report generato il $generatedAt - Pagina ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          // Intestazione
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _dark,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'HORIZON3.AI - REPORT PENTEST',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'NodeZero Operations Panel',
                      style: const pw.TextStyle(color: PdfColors.grey400, fontSize: 10),
                    ),
                  ],
                ),
                pw.Text(
                  type,
                  style: pw.TextStyle(
                    color: PdfColor.fromInt(0xFF00E5FF),
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Info operazione
          pw.Text(name,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerCount: 0,
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            columnWidths: {
              0: const pw.FixedColumnWidth(120),
              1: const pw.FlexColumnWidth(),
            },
            data: [
              ['UUID Operazione', opId],
              ['Stato', state],
              ['Tipo', type],
              ['Data avvio', _formatDate(detail['launched_at']?.toString())],
              ['Data conclusione', _formatDate(detail['completed_at']?.toString())],
            ],
          ),
          pw.SizedBox(height: 16),

          // Metriche
          pw.Row(
            children: [
              _metricBox('DEBOLEZZE', weaknessCount.toString(),
                  weaknessCount > 0 ? _high : _low),
              pw.SizedBox(width: 10),
              _metricBox('CREDENZIALI RACCOLTE', credentials.toString(),
                  credentials > 0 ? _medium : _low),
              pw.SizedBox(width: 10),
              _metricBox('ACCESSI CON CREDENZIALI', credAccess.toString(),
                  credAccess > 0 ? _accent : _low),
            ],
          ),
          pw.SizedBox(height: 20),

          // Riepilogo severità
          pw.Text('Riepilogo per severità',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
            headers: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'TOTALE'],
            data: [
              [
                counts['CRITICAL'].toString(),
                counts['HIGH'].toString(),
                counts['MEDIUM'].toString(),
                counts['LOW'].toString(),
                weaknesses.length.toString(),
              ],
            ],
          ),
          pw.SizedBox(height: 20),

          // Elenco debolezze
          pw.Text('Debolezze rilevate',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (sorted.isEmpty)
            pw.Text(
              'Nessuna debolezza rilevata in questa operazione.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            )
          else
            for (final w in sorted) ..._weaknessWidgets(w),
        ],
      ),
    );

    final fileName =
        'report_${_sanitizeFileName(name)}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    await Printing.sharePdf(bytes: await doc.save(), filename: fileName);
  }

  pw.Widget _metricBox(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold, color: color)),
            pw.SizedBox(height: 4),
            pw.Text(label,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          ],
        ),
      ),
    );
  }

  // Restituisce il contenuto di una debolezza come lista di widget "piatti"
  // (non incapsulati in un Container/Column rigido). Questo è essenziale:
  // MultiPage impagina spezzando TRA i widget di primo livello, e sa dividere
  // su più pagine un pw.Paragraph (testo scorrevole). Con descrizioni lunghe
  // dei pentest reali, un riquadro rigido supererebbe l'altezza della pagina
  // e, non essendo divisibile, bloccherebbe l'impaginazione (si vedeva solo
  // la prima pagina).
  List<pw.Widget> _weaknessWidgets(Map<String, dynamic> w) {
    final severity = (w['severity']?.toString() ?? 'LOW').toUpperCase();
    final color = _severityColor(severity);
    final name = w['name']?.toString() ?? 'Debolezza sconosciuta';
    final category = w['category']?.toString() ?? 'N/D';
    final asset = w['affected_asset']?.toString() ?? 'N/D';
    final description = w['description']?.toString() ?? '';

    return [
      pw.SizedBox(height: 6),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(severity,
                style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(name,
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
      pw.SizedBox(height: 2),
      pw.Text('Categoria: $category  |  Asset: $asset',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      if (description.isNotEmpty)
        pw.Paragraph(
          text: description,
          style: const pw.TextStyle(fontSize: 8.5),
          margin: const pw.EdgeInsets.only(top: 3, bottom: 2),
        ),
      pw.Divider(color: PdfColors.grey300, thickness: 0.5, height: 10),
    ];
  }

  // ---------------------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------------------

  String _csvEscape(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(';') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  Future<void> exportCsv({
    required Map<String, dynamic> detail,
    required List<Map<String, dynamic>> weaknesses,
  }) async {
    final buffer = StringBuffer();
    // Separatore ';' per compatibilità con Excel in locale italiano.
    buffer.writeln('op_id;op_name;weakness_id;name;category;severity;affected_asset;description');

    final opId = detail['op_id']?.toString() ?? '';
    final opName = detail['name']?.toString() ?? '';

    for (final w in _sortedWeaknesses(weaknesses)) {
      buffer.writeln([
        opId,
        opName,
        w['weakness_id'],
        w['name'],
        w['category'],
        w['severity'],
        w['affected_asset'],
        w['description'],
      ].map(_csvEscape).join(';'));
    }

    // BOM UTF-8 così Excel riconosce correttamente gli accenti.
    final bytes = Uint8List.fromList(utf8.encode('﻿${buffer.toString()}'));
    final fileName =
        'debolezze_${_sanitizeFileName(opName)}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: 'csv',
      mimeType: MimeType.csv,
    );
  }
}
