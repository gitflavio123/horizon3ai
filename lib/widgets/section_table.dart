import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Definizione di una colonna della tabella di sezione.
/// [value] estrae il testo da mostrare dalla riga dati.
/// [isSeverity] applica un chip colorato in base alla severità/score.
class SectionColumn {
  final String label;
  final String Function(Map<String, dynamic> row) value;
  final bool isSeverity;

  const SectionColumn(this.label, this.value, {this.isSeverity = false});
}

/// Widget riutilizzabile che rende una sezione del pentest (Credentials, Hosts,
/// Services, ...) gestendo gli stati loading / error / empty e una tabella
/// scrollabile orizzontalmente guidata dalla configurazione delle colonne.
///
/// È volutamente "resiliente": ogni sezione carica i propri dati in modo
/// indipendente, quindi un errore GraphQL su una sezione (es. nome campo diverso
/// nel tenant) resta isolato e mostra un messaggio con pulsante Riprova, senza
/// compromettere le altre schede.
class SectionTable extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final List<Map<String, dynamic>> rows;
  final List<SectionColumn> columns;
  final VoidCallback onRetry;
  final String emptyMessage;

  const SectionTable({
    super.key,
    required this.isLoading,
    required this.error,
    required this.rows,
    required this.columns,
    required this.onRetry,
    this.emptyMessage = 'Nessun dato disponibile per questa sezione.',
  });

  Color _severityColor(String raw) {
    switch (raw.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFD32F2F);
      case 'HIGH':
        return const Color(0xFFFF5252);
      case 'MEDIUM':
        return const Color(0xFFFFAB40);
      case 'LOW':
        return const Color(0xFF42A5F5);
      default:
        return const Color(0xFF90A4AE);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
          ),
        ),
      );
    }

    if (error != null) {
      // Caso permessi: alcune sezioni (es. Certificates) non sono accessibili
      // con una API key standard → messaggio neutro, non un errore "rosso".
      final lower = error!.toLowerCase();
      if (lower.contains('403') || lower.contains('not authorized')) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, color: Color(0xFF90A4AE), size: 40),
                const SizedBox(height: 12),
                Text(
                  'Sezione non disponibile con questa API key',
                  style: GoogleFonts.outfit(
                      fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Richiede permessi non inclusi nel tipo di chiave attuale.',
                  style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: Color(0xFFFF5252), size: 40),
              const SizedBox(height: 12),
              Text(
                'Errore nel caricamento della sezione',
                style: GoogleFonts.outfit(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error!,
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inbox_outlined,
                  color: Color(0xFF546074), size: 40),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Header con conteggio + tabella scrollabile in orizzontale e verticale.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            '${rows.length} ${rows.length == 1 ? "risultato" : "risultati"}',
            style: GoogleFonts.shareTechMono(
              color: const Color(0xFF00E5FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF181C2E)),
                dividerThickness: 0.4,
                headingRowHeight: 42,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 60,
                columnSpacing: 26,
                border: TableBorder(
                  horizontalInside:
                      BorderSide(color: const Color(0xFF22263C).withOpacity(0.6)),
                ),
                columns: columns
                    .map((c) => DataColumn(
                          label: Text(
                            c.label.toUpperCase(),
                            style: GoogleFonts.shareTechMono(
                              color: const Color(0xFF90A4AE),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ))
                    .toList(),
                rows: rows.map((row) {
                  return DataRow(
                    cells: columns.map((c) {
                      final text = c.value(row);
                      if (c.isSeverity) {
                        final color = _severityColor(text);
                        return DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withOpacity(0.35)),
                            ),
                            child: Text(
                              text.isEmpty ? 'N/D' : text.toUpperCase(),
                              style: GoogleFonts.shareTechMono(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }
                      return DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            text.isEmpty ? '—' : text,
                            style: const TextStyle(
                                color: Color(0xFFECEFF1), fontSize: 12.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
