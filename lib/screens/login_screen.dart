import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController(
    text: const String.fromEnvironment('H3_API_KEY'),
  );
  String _selectedRegion = 'EU';

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _pasteApiKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _apiKeyController.text = text;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    // If user inputs nothing or 'MOCK', it will login in Mock Mode
    final apiKey = _apiKeyController.text.trim().isEmpty ? 'MOCK' : _apiKeyController.text.trim();

    final success = await auth.login(apiKey, _selectedRegion);

    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Errore di autenticazione'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF070913),
              Color(0xFF0F111E),
              Color(0xFF0A0C14),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand / Logo Header — no frame, glows softly into the dark background
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5AB992).withOpacity(0.35),
                              blurRadius: 48,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/tesys_logo.png',
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Center(
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFFFFFFF), Color(0xFFB9E4D3)],
                        ).createShader(bounds),
                        child: Text(
                          'HORIZON3.AI',
                          style: GoogleFonts.shareTechMono(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        'NodeZero API Integration',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          color: const Color(0xFF5AB992),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Login Card (Glassmorphism design)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141724).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF22263C),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5AB992).withOpacity(0.03),
                            blurRadius: 20,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configura Connessione Portal',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Region Selector Label
                          const Text(
                            'Area Geografica (Region)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF90A4AE),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Region Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRegion,
                            dropdownColor: const Color(0xFF141724),
                            isExpanded: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              prefixIcon: Icon(
                                Icons.public,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'EU',
                                child: Text(
                                  'Europe (portal.horizon3ai.eu)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'US',
                                child: Text(
                                  'United States (portal.horizon3ai.com)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedRegion = val;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 20),

                          // API Key Input Label
                          const Text(
                            'API Key Horizon3',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF90A4AE),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // API Key Input
                          TextFormField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: 'Inserisci o lascia vuoto per modalità DEMO',
                              prefixIcon: const Icon(Icons.key, color: Color(0xFF7C4DFF)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.paste, color: Color(0xFF90A4AE)),
                                tooltip: 'Incolla',
                                onPressed: _pasteApiKey,
                              ),
                            ),
                            style: GoogleFonts.shareTechMono(color: Colors.white),
                          ),
                          const SizedBox(height: 12),

                          // Quick Info Box
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5AB992).withOpacity(0.03),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF5AB992).withOpacity(0.1),
                              ),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Color(0xFF5AB992),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Lasciare vuota la chiave avvia l\'applicazione in modalità DEMO con dati simulati.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF90A4AE),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Login/Submit Button
                          Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [Color(0xFF5AB992), Color(0xFF3E8A6C)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF5AB992).withOpacity(0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: auth.isLoading ? null : _submit,
                                child: Center(
                                  child: auth.isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                          ),
                                        )
                                      : Text(
                                          'COLLEGA API',
                                          style: GoogleFonts.shareTechMono(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                            color: Colors.black,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Quick guide text
                    Center(
                      child: Text(
                        'Come ottenere una API Key:',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF90A4AE),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Accedi a Settings > API Keys nel portale Horizon3.\nGenera una chiave con ruolo Admin/Developer o Runner.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF607D8B),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
