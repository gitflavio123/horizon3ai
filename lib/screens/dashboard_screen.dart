import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/pentest_provider.dart';
import 'new_scan_screen.dart';
import 'pentest_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _statusFilter = 'ALL';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _loadData() {
    final auth = context.read<AuthProvider>();
    context.read<PentestProvider>().loadPentests(
          apiKey: auth.apiKey ?? '',
          region: auth.region,
          token: auth.token ?? '',
        );
  }

  void _openNewScanScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewScanScreen()),
    );
  }

  // TEMP DEBUG: shows the raw schema introspection result in-app (rather
  // than only in the flutter run console) so it can be copied and shared.
  void _showDebugResultDialog(BuildContext context, String result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141724),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF22263C)),
        ),
        title: const Text('Schema GraphQL', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              result,
              style: GoogleFonts.shareTechMono(color: const Color(0xFFECEFF1), fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copiato negli appunti.')),
              );
            },
            child: const Text('COPIA'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CHIUDI'),
          ),
        ],
      ),
    );
  }

  // The real NodeZero API returns 'done' rather than 'COMPLETED' for a
  // finished operation; normalize known aliases before comparing states.
  String _normalizeState(String? raw) {
    final upper = (raw ?? '').toUpperCase();
    if (upper == 'DONE') return 'COMPLETED';
    return upper;
  }

  // Only these two are confirmed end-states; any other value (RUNNING,
  // PREPARING, or future ones) counts as still active work in progress.
  bool _isTerminal(String normalizedState) =>
      normalizedState == 'COMPLETED' || normalizedState == 'FAILED';

  Color _getStatusColor(String state) {
    switch (_normalizeState(state)) {
      case 'COMPLETED':
        return const Color(0xFF00E676); // Green
      case 'FAILED':
        return const Color(0xFFFF5252); // Red
      case 'QUEUED':
        return const Color(0xFF90A4AE); // Grey
      default:
        // Any other non-terminal state (RUNNING, PREPARING, ...) is active work.
        return const Color(0xFFFFAB40); // Amber/Orange
    }
  }

  IconData _getStatusIcon(String state) {
    switch (_normalizeState(state)) {
      case 'COMPLETED':
        return Icons.check_circle_outline;
      case 'FAILED':
        return Icons.error_outline;
      case 'QUEUED':
        return Icons.schedule;
      default:
        return Icons.donut_large;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pentestProv = context.watch<PentestProvider>();

    // Filtering logic
    final filteredList = pentestProv.pentests.where((item) {
      final normalizedState = _normalizeState(item['state']?.toString());
      final matchesStatus = _statusFilter == 'ALL' ||
          (_statusFilter == 'RUNNING'
              // The real API's in-progress vocabulary isn't fully known
              // (preparing, processing, ...), so "In Corso" matches anything
              // that isn't queued or a terminal state, not a literal 'RUNNING'.
              ? normalizedState != 'QUEUED' && !_isTerminal(normalizedState)
              : normalizedState == _statusFilter);
      final matchesSearch = item['name']
              ?.toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ??
          false;
      return matchesStatus && matchesSearch;
    }).toList();

    // Summary counters
    final totalOps = pentestProv.pentests.length;
    final runningOps = pentestProv.pentests.where((p) {
      final normalized = _normalizeState(p['state']?.toString());
      return normalized != 'QUEUED' && !_isTerminal(normalized);
    }).length;
    final completedOps = pentestProv.pentests
        .where((p) => _normalizeState(p['state']?.toString()) == 'COMPLETED')
        .length;
    final totalWeaknesses = pentestProv.pentests.fold<int>(
        0, (sum, p) => sum + (p['weaknesses_count'] as int? ?? 0));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D101D),
        elevation: 0,
        leadingWidth: 52,
        titleSpacing: 4,
        leading: const Padding(
          padding: EdgeInsets.all(6.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
            child: Padding(
              padding: EdgeInsets.all(4.0),
              child: Image(
                image: AssetImage('assets/images/tesys_logo.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: auth.isMock
                    ? const Color(0xFF7C4DFF).withOpacity(0.15)
                    : const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: auth.isMock ? const Color(0xFF7C4DFF) : const Color(0xFF00E5FF),
                  width: 1,
                ),
              ),
              child: Text(
                auth.isMock ? 'DEMO' : 'ACTIVE',
                style: GoogleFonts.shareTechMono(
                  fontSize: 12,
                  color: auth.isMock ? const Color(0xFFB39DDB) : const Color(0xFF00E5FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Horizon3 - ${auth.region}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // TEMP DEBUG: prints the real GraphQL schema to the console so the
          // hand-written queries can be corrected. Remove once fixed.
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, color: Color(0xFFFFAB40)),
            tooltip: 'Debug: Ispeziona Schema GraphQL',
            onPressed: () async {
              final result = await pentestProv.debugIntrospectSchema(
                region: auth.region,
                token: auth.token ?? '',
              );
              if (context.mounted) {
                _showDebugResultDialog(context, result);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.rocket_launch, color: Color(0xFF00E5FF)),
            onPressed: () => _openNewScanScreen(context),
            tooltip: 'Avvia Pentest',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFF5252)),
            onPressed: () {
              auth.logout();
              pentestProv.clear();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadData();
        },
        color: const Color(0xFF00E5FF),
        backgroundColor: const Color(0xFF141724),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome Header
              Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Image(
                      image: const AssetImage('assets/images/tesys_logo.png'),
                      height: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'NodeZero Operations Panel',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Analisi e monitoraggio dei penetration test attivi e passati.',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF90A4AE),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),

              // KPI Stats Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final double cardWidth = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildKpiCard('OP TOTALI', totalOps.toString(), Icons.folder_open, const Color(0xFF7C4DFF), cardWidth),
                      _buildKpiCard('IN ESECUZIONE', runningOps.toString(), Icons.donut_large, const Color(0xFFFFAB40), cardWidth),
                      _buildKpiCard('COMPLETATI', completedOps.toString(), Icons.task_alt, const Color(0xFF00E676), cardWidth),
                      _buildKpiCard('DEBOLEZZE TROVATE', totalWeaknesses.toString(), Icons.bug_report, const Color(0xFFFF5252), cardWidth),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),

              // Search & Filter section
              Text(
                'Elenco Pentests',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              // Search Bar
              TextField(
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
                decoration: const InputDecoration(
                  hintText: 'Cerca operazione per nome...',
                  prefixIcon: Icon(Icons.search, color: Color(0xFF607D8B)),
                ),
              ),
              const SizedBox(height: 12),

              // Status Filters (Horizontal row)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('ALL', 'Tutti'),
                    _buildFilterChip('RUNNING', 'In Corso'),
                    _buildFilterChip('COMPLETED', 'Completati'),
                    _buildFilterChip('FAILED', 'Falliti'),
                    _buildFilterChip('QUEUED', 'In Coda'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Pentests List
              if (pentestProv.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48.0),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                    ),
                  ),
                )
              else if (pentestProv.errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 36),
                      const SizedBox(height: 8),
                      Text(
                        'Errore API',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pentestProv.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFECEFF1)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5252),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Riprova'),
                      )
                    ],
                  ),
                )
              else if (filteredList.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.layers_clear_outlined, color: const Color(0xFF607D8B), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Nessuna operazione trovata',
                          style: GoogleFonts.outfit(color: const Color(0xFF90A4AE), fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final item = filteredList[index];
                    final opId = item['op_id'] ?? '';
                    final name = item['name'] ?? 'Operazione Senza Nome';
                    final state = item['state'] ?? 'UNKNOWN';
                    final type = item['op_type'] ?? 'INTERNAL';
                    final weaknesses = item['weaknesses_count'] as int? ?? 0;
                    final launchedAtRaw = item['launched_at'];

                    String launchedStr = 'Non avviato';
                    if (launchedAtRaw != null) {
                      try {
                        final parsed = DateTime.parse(launchedAtRaw);
                        launchedStr = DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
                      } catch (_) {}
                    }

                    final statusColor = _getStatusColor(state);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PentestDetailScreen(opId: opId),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status & OpType row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_getStatusIcon(state), size: 14, color: statusColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          state,
                                          style: GoogleFonts.shareTechMono(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22263C),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      type,
                                      style: GoogleFonts.shareTechMono(
                                        color: const Color(0xFF00E5FF),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Name
                              Text(
                                name,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Launched at time
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 12, color: Color(0xFF607D8B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Avvio: $launchedStr',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B)),
                                  ),
                                ],
                              ),
                              const Divider(height: 24, color: Color(0xFF22263C)),

                              // Metrics footer
                              Row(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.bug_report,
                                        size: 16,
                                        color: weaknesses > 0 ? const Color(0xFFFF5252) : const Color(0xFF607D8B),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$weaknesses Debolezze',
                                        style: TextStyle(
                                          color: weaknesses > 0 ? Colors.white : const Color(0xFF90A4AE),
                                          fontWeight: weaknesses > 0 ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Dettagli',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF00E5FF),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFF00E5FF)),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewScanScreen(context),
        label: Text(
          'NUOVO TEST',
          style: GoogleFonts.shareTechMono(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: Colors.black,
      ),
    );
  }

  Widget _buildFilterChip(String status, String label) {
    final isSelected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        selected: isSelected,
        label: Text(label),
        labelStyle: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        selectedColor: const Color(0xFF00E5FF),
        backgroundColor: const Color(0xFF141724),
        checkmarkColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF22263C),
            width: 1,
          ),
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _statusFilter = status;
            });
          }
        },
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141724),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22263C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.shareTechMono(
                  fontSize: 11,
                  color: const Color(0xFF90A4AE),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Icon(icon, color: color.withOpacity(0.6), size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.shareTechMono(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
