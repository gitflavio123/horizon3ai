import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/pentest_provider.dart';
import 'pentest_detail_screen.dart';

enum _LaunchPhase { idle, verifying, launching }

class NewScanScreen extends StatefulWidget {
  const NewScanScreen({super.key});

  @override
  State<NewScanScreen> createState() => _NewScanScreenState();
}

class _NewScanScreenState extends State<NewScanScreen> {
  late final TextEditingController _nameController;
  final TextEditingController _targetsController = TextEditingController();
  String? _selectedTemplateId;

  _LaunchPhase _phase = _LaunchPhase.idle;
  List<String> _invalidTargets = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: 'Scan - ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      context.read<PentestProvider>().loadTemplates(
        apiKey: auth.apiKey ?? '',
        region: auth.region,
        token: auth.token ?? '',
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetsController.dispose();
    super.dispose();
  }

  List<String> get _parsedTargets => _targetsController.text
      .split(RegExp(r'[,\n]'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  static final RegExp _ipv4Pattern = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(/\d{1,2})?$',
  );
  static final RegExp _hostnamePattern = RegExp(
    r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  bool _isValidTarget(String target) {
    if (_ipv4Pattern.hasMatch(target)) {
      final octets = target.split('/').first.split('.');
      return octets.every(
        (o) => int.tryParse(o) != null && int.parse(o) <= 255,
      );
    }
    return _hostnamePattern.hasMatch(target);
  }

  Future<void> _launch() async {
    final targets = _parsedTargets;
    final invalid = targets.where((t) => !_isValidTarget(t)).toList();

    setState(() {
      _phase = _LaunchPhase.verifying;
      _invalidTargets = invalid;
    });

    // Gives the verification step a visible moment on screen instead of
    // flashing past instantly, so the user can see each stage progress.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    if (invalid.isNotEmpty) {
      setState(() => _phase = _LaunchPhase.idle);
      return;
    }

    setState(() => _phase = _LaunchPhase.launching);

    final auth = context.read<AuthProvider>();
    final prov = context.read<PentestProvider>();

    final res = await prov.triggerPentest(
      apiKey: auth.apiKey ?? '',
      region: auth.region,
      token: auth.token ?? '',
      opName: _nameController.text.trim(),
      templateId: _selectedTemplateId!,
      targets: targets,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Operazione "${res['name']}" avviata con successo!'),
          backgroundColor: const Color(0xFF00E676),
        ),
      );
      if (res['op_id'] != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PentestDetailScreen(opId: res['op_id']),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } else {
      setState(() => _phase = _LaunchPhase.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Errore: ${res['error'] ?? 'Impossibile avviare il test'}',
          ),
          backgroundColor: const Color(0xFFFF5252),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<PentestProvider>();

    if (_selectedTemplateId == null && prov.templates.isNotEmpty) {
      _selectedTemplateId = prov.templates.first['template_id'];
    }

    final targets = _parsedTargets;
    final canLaunch =
        _phase == _LaunchPhase.idle &&
        _nameController.text.trim().isNotEmpty &&
        targets.isNotEmpty &&
        _selectedTemplateId != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D101D),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Color(0xFF00E5FF)),
            const SizedBox(width: 10),
            Text(
              'Nuova Scansione',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Nome Operazione'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'E.g., Scansione Mensile',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),

            _sectionLabel('Target'),
            const SizedBox(height: 4),
            const Text(
              'Uno o più target (IP, dominio o CIDR), separati da virgola o a capo.',
              style: TextStyle(fontSize: 12, color: Color(0xFF607D8B)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _targetsController,
              onChanged: (_) => setState(() {}),
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: '192.168.1.0/24\nscan.example.com',
              ),
              style: GoogleFonts.shareTechMono(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
            if (targets.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: targets.map((t) {
                  final isInvalid = _invalidTargets.contains(t);
                  return Chip(
                    avatar: isInvalid
                        ? const Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Color(0xFFFF5252),
                          )
                        : null,
                    label: Text(
                      t,
                      style: GoogleFonts.shareTechMono(
                        fontSize: 12,
                        color: isInvalid
                            ? const Color(0xFFFF5252)
                            : Colors.white,
                      ),
                    ),
                    backgroundColor: const Color(0xFF22263C),
                    side: BorderSide(
                      color: isInvalid
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF2E3456),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (_invalidTargets.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Formato non valido per: ${_invalidTargets.join(', ')}',
                style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),

            _sectionLabel('Seleziona Operation Template'),
            const SizedBox(height: 8),
            _buildTemplateSelector(auth, prov),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 16,
                    color: Color(0xFFFF5252),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assicurati di essere autorizzato a testare i target inseriti. L\'uso improprio può violare policy o normative.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFB0BEC5),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            if (_phase == _LaunchPhase.idle)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canLaunch ? _launch : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'AVVIA SCANSIONE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              _buildLaunchProgressPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildLaunchProgressPanel() {
    final verifying = _phase == _LaunchPhase.verifying;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22263C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPhaseStep(
                label: 'VERIFICA',
                active: verifying,
                done: !verifying,
              ),
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: !verifying
                      ? const Color(0xFF00E676)
                      : const Color(0xFF22263C),
                ),
              ),
              _buildPhaseStep(label: 'LANCIO', active: !verifying, done: false),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            verifying
                ? 'Verifica target e configurazione in corso...'
                : 'Avvio pentest in corso sull\'endpoint selezionato...',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              minHeight: 6,
              backgroundColor: Color(0xFF22263C),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseStep({
    required String label,
    required bool active,
    required bool done,
  }) {
    final color = done
        ? const Color(0xFF00E676)
        : (active ? const Color(0xFF00E5FF) : const Color(0xFF607D8B));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done
              ? Icons.check_circle
              : (active ? Icons.autorenew : Icons.radio_button_unchecked),
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.shareTechMono(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: Color(0xFF90A4AE),
    ),
  );

  Widget _buildTemplateSelector(AuthProvider auth, PentestProvider prov) {
    if (prov.isLoadingTemplates) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
          ),
        ),
      );
    }
    if (prov.templatesErrorMessage != null) {
      return Column(
        children: [
          Text(
            'Errore caricamento template: ${prov.templatesErrorMessage}',
            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              prov.loadTemplates(
                apiKey: auth.apiKey ?? '',
                region: auth.region,
                token: auth.token ?? '',
              );
            },
            child: const Text('Riprova'),
          ),
        ],
      );
    }
    if (prov.templates.isEmpty) {
      return const Text(
        'Nessun template disponibile nel tuo account. Creane uno sul portale Horizon3.',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedTemplateId,
      dropdownColor: const Color(0xFF141724),
      isExpanded: true,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      items: prov.templates.map((t) {
        return DropdownMenuItem<String>(
          value: t['template_id'],
          child: Text(
            t['name'] ?? '',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        );
      }).toList(),
      onChanged: (val) => setState(() => _selectedTemplateId = val),
    );
  }
}
