import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // GraphQL query definitions as configurable constants
  static const String listPentestsQuery = r'''
    query GetPentests {
      pentests_page {
        pentests {
          op_id
          name
          state
          op_type
          launched_at
          completed_at
          weaknesses_count
        }
      }
    }
  ''';

  static const String getPentestDetailQuery = r'''
    query GetPentest($op_id: String!) {
      pentest(op_id: $op_id) {
        op_id
        name
        state
        op_type
        launched_at
        completed_at
        weaknesses_count
        credentials_count
        cred_access_count
      }
    }
  ''';

  // GraphQL query to get available Operation Templates (pre-configured scan configs)
  static const String getTemplatesQuery = r'''
    query GetOperationTemplates {
      op_templates_page {
        op_templates {
          uuid
          op_template_name
          op_type
        }
      }
    }
  ''';

  // GraphQL query to get the detailed findings/weaknesses of a pentest
  static const String getWeaknessesQuery = r'''
    query GetWeaknesses($op_id: String!) {
      pentest(op_id: $op_id) {
        weaknesses {
          weakness_id
          name
          category
          severity
          affected_asset
          description
        }
      }
    }
  ''';

  // GraphQL mutation to launch/schedule a new pentest operation
  static const String createOpMutation = r'''
    mutation CreatePentest($op_name: String!, $op_template_uuid: String!) {
      create_op(
        op_template_uuid: $op_template_uuid
        schedule_op_form: { op_name: $op_name }
      ) {
        op {
          op_id
          op_name
          op_state
        }
      }
    }
  ''';

  // Base URL resolution based on region
  String _getBaseUrl(String region) {
    if (region.toUpperCase() == 'US') {
      return 'https://api.gateway.horizon3ai.com/v1';
    }
    return 'https://api.gateway.horizon3ai.eu/v1';
  }

  // Check if using Mock mode
  bool _isMockKey(String apiKey) {
    return apiKey.trim().toUpperCase() == 'MOCK' || apiKey.trim().isEmpty;
  }

  // 1. Authenticate API Key and return JWT Token
  Future<Map<String, dynamic>> authenticate(String apiKey, String region) async {
    if (_isMockKey(apiKey)) {
      // Mock Authentication
      await Future.delayed(const Duration(seconds: 1));
      return {
        'success': true,
        'token': 'mock-jwt-token-xyz',
        'isMock': true,
      };
    }

    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/auth');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'key': apiKey.trim()}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'token': data['token'] ?? '',
          'isMock': false,
        };
      } else {
        final errorMsg = _parseError(response.body);
        return {
          'success': false,
          'error': 'Auth failed (${response.statusCode}): $errorMsg',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network connection error: $e',
      };
    }
  }

  // 2. Fetch Pentests List
  Future<List<Map<String, dynamic>>> fetchPentests({
    required String apiKey,
    required String region,
    required String token,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 800));
      return _mockPentests;
    }

    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': listPentestsQuery,
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data != null) {
          var list = data['pentests'];
          if (list == null && data['pentests_page'] != null) {
            list = data['pentests_page']['pentests'];
          }
          if (list != null) {
            return List<Map<String, dynamic>>.from(list);
          }
        }
        // Handle GraphQL errors returned in JSON
        if (body['errors'] != null) {
          final errors = body['errors'] as List;
          throw Exception(errors.first['message'] ?? 'GraphQL Query Error');
        }
        throw Exception('Invalid response structure');
      } else {
        throw Exception('HTTP error ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('fetchPentests error: $e. Falling back to structured response or throwing...');
      rethrow;
    }
  }

  // 3. Fetch Pentest Details
  Future<Map<String, dynamic>?> fetchPentestDetail({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 600));
      return _mockPentestDetails[opId] ?? _mockPentests.firstWhere((p) => p['op_id'] == opId, orElse: () => {});
    }

    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': getPentestDetailQuery,
          'variables': {'op_id': opId},
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data != null && data['pentest'] != null) {
          return Map<String, dynamic>.from(data['pentest']);
        }
        if (body['errors'] != null) {
          final errors = body['errors'] as List;
          throw Exception(errors.first['message'] ?? 'GraphQL Query Error');
        }
        return null;
      } else {
        throw Exception('HTTP error ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('fetchPentestDetail error: $e');
      rethrow;
    }
  }

  // 3b. Fetch the list of weaknesses/findings detected during a pentest
  Future<List<Map<String, dynamic>>> fetchWeaknesses({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 500));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      final opType = detail?['op_type'] as String? ?? 'INTERNAL';
      if (count == 0) return [];
      return _generateMockWeaknesses(opId, count, opType);
    }

    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': getWeaknessesQuery,
          'variables': {'op_id': opId},
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data != null && data['pentest'] != null && data['pentest']['weaknesses'] != null) {
          return List<Map<String, dynamic>>.from(data['pentest']['weaknesses']);
        }
        if (body['errors'] != null) {
          final errors = body['errors'] as List;
          throw Exception(errors.first['message'] ?? 'GraphQL Query Error');
        }
        return [];
      } else {
        throw Exception('HTTP error ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('fetchWeaknesses error: $e');
      rethrow;
    }
  }

  // TEMP DEBUG: introspects the real GraphQL schema so the hand-written
  // queries/mutations in this file can be corrected against actual field
  // names. Remove once the schema mismatch is fixed.
  static const String _debugIntrospectionQuery = r'''
    query IntrospectDebug {
      __schema {
        mutationType {
          fields {
            name
            args { name type { kind name ofType { kind name ofType { kind name } } } }
            type { kind name ofType { kind name } }
          }
        }
        queryType {
          fields {
            name
            args { name type { kind name ofType { kind name } } }
            type { kind name ofType { kind name } }
          }
        }
      }
      ScheduleOpFormInput: __type(name: "ScheduleOpFormInput") {
        inputFields { name type { kind name ofType { kind name ofType { kind name } } } }
      }
      Op: __type(name: "Op") {
        fields { name type { kind name ofType { kind name } } }
      }
      Pentest: __type(name: "Pentest") {
        fields { name type { kind name ofType { kind name } } }
      }
      OpTemplate: __type(name: "OpTemplate") {
        fields { name type { kind name ofType { kind name } } }
      }
    }
  ''';

  Future<String> debugIntrospectSchema({
    required String region,
    required String token,
  }) async {
    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': _debugIntrospectionQuery}),
      );
      final result = 'HTTP ${response.statusCode}\n${response.body}';
      print('=== SCHEMA INTROSPECTION ===\n$result\n=== END SCHEMA INTROSPECTION ===');
      return result;
    } catch (e) {
      return 'Introspection request failed: $e';
    }
  }

  // Helper to parse errors from JSON
  String _parseError(String body) {
    try {
      final map = jsonDecode(body);
      if (map['errors'] is List && (map['errors'] as List).isNotEmpty) {
        return map['errors'][0]['message']?.toString() ?? body;
      }
      return map['message'] ?? map['error'] ?? body;
    } catch (_) {
      return body;
    }
  }

  // 4. Fetch Operation Templates
  Future<List<Map<String, dynamic>>> fetchOperationTemplates({
    required String apiKey,
    required String region,
    required String token,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 500));
      return _mockTemplates;
    }

    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': getTemplatesQuery,
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data != null) {
          var list = data['op_templates'];
          if (list == null && data['op_templates_page'] != null) {
            list = data['op_templates_page']['op_templates'];
          }
          if (list != null) {
            return List<Map<String, dynamic>>.from(list.map((item) => {
              'template_id': item['uuid'],
              'name': item['op_template_name'] ?? item['name'] ?? 'Senza Nome',
              'description': item['description'] ?? 'Nessuna descrizione fornita.',
              'op_type': item['op_type'] ?? 'INTERNAL',
            }));
          }
        }
        if (body['errors'] != null) {
          final errors = body['errors'] as List;
          throw Exception(errors.first['message'] ?? 'GraphQL Query Error');
        }
        throw Exception('Invalid response structure');
      } else {
        throw Exception('HTTP error ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('fetchOperationTemplates error: $e');
      rethrow;
    }
  }

  // 5. Launch/Create Pentest
  Future<Map<String, dynamic>> launchPentest({
    required String apiKey,
    required String region,
    required String token,
    required String opName,
    required String templateId,
    List<String> targets = const [],
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 1500));
      final newOpId = 'op-eu-${_mockPentests.length + 7500}';
      final selectedTpl = _mockTemplates.firstWhere(
        (t) => t['template_id'] == templateId,
        orElse: () => {'op_type': 'INTERNAL'},
      );

      final newOp = {
        'op_id': newOpId,
        'name': opName,
        'state': 'QUEUED',
        'op_type': selectedTpl['op_type'],
        'launched_at': null,
        'completed_at': null,
        'weaknesses_count': 0,
        'targets': targets,
      };

      // Inject into mock cache
      _mockPentests.insert(0, newOp);
      _mockPentestDetails[newOpId] = {
        ...newOp,
        'credentials_count': 0,
        'cred_access_count': 0,
      };

      // Simulate a real scan lifecycle so the mock op can actually be watched
      // progressing to completion and producing viewable results.
      _simulateMockScanProgress(newOpId, selectedTpl['op_type'] as String? ?? 'INTERNAL');

      return {
        'success': true,
        'op_id': newOpId,
        'name': opName,
      };
    }

    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': createOpMutation,
          'variables': {
            'op_name': opName,
            'op_template_uuid': templateId,
          },
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        if (data != null && data['create_op'] != null && data['create_op']['op'] != null) {
          final op = data['create_op']['op'];
          return {
            'success': true,
            'op_id': op['op_id'],
            'name': op['op_name'] ?? op['name'],
          };
        }
        if (body['errors'] != null) {
          final errors = body['errors'] as List;
          return {
            'success': false,
            'error': errors.first['message'] ?? 'GraphQL Mutation Error',
          };
        }
        return {
          'success': false,
          'error': 'Response format unexpected',
        };
      } else {
        print('launchPentest HTTP ${response.statusCode} body: ${response.body}');
        return {
          'success': false,
          'error': 'HTTP error ${response.statusCode}: ${_parseError(response.body)}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Advances a mock op through QUEUED -> RUNNING -> COMPLETED on timers, so a
  // launched demo scan can actually be watched finishing and yielding results.
  void _simulateMockScanProgress(String opId, String opType) {
    Timer(const Duration(seconds: 5), () {
      final launchedAt = DateTime.now().toUtc().toIso8601String();
      final idx = _mockPentests.indexWhere((p) => p['op_id'] == opId);
      if (idx != -1) {
        _mockPentests[idx]['state'] = 'RUNNING';
        _mockPentests[idx]['launched_at'] = launchedAt;
      }
      final detail = _mockPentestDetails[opId];
      if (detail != null) {
        detail['state'] = 'RUNNING';
        detail['launched_at'] = launchedAt;
      }
    });

    Timer(const Duration(seconds: 18), () {
      final completedAt = DateTime.now().toUtc().toIso8601String();
      final weaknessCount = 3 + (opId.hashCode.abs() % 6);
      final idx = _mockPentests.indexWhere((p) => p['op_id'] == opId);
      if (idx != -1) {
        _mockPentests[idx]['state'] = 'COMPLETED';
        _mockPentests[idx]['completed_at'] = completedAt;
        _mockPentests[idx]['weaknesses_count'] = weaknessCount;
      }
      final detail = _mockPentestDetails[opId];
      if (detail != null) {
        detail['state'] = 'COMPLETED';
        detail['completed_at'] = completedAt;
        detail['weaknesses_count'] = weaknessCount;
        detail['credentials_count'] = (weaknessCount / 3).floor();
        detail['cred_access_count'] = (weaknessCount / 6).floor();
      }
    });
  }

  // Deterministically derives a findings list from a weaknesses_count so mock
  // pentests always show results consistent with their summary counters.
  List<Map<String, dynamic>> _generateMockWeaknesses(String opId, int count, String opType) {
    const severities = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];
    final categories = opType == 'EXTERNAL'
        ? ['Applicazione Web', 'Servizio Esposto', 'Misconfigurazione TLS', 'Divulgazione Informazioni']
        : ['Active Directory', 'Esposizione Credenziali', 'Misconfigurazione', 'Software Non Aggiornato'];

    return List.generate(count, (i) {
      final severity = severities[i % severities.length];
      final category = categories[i % categories.length];
      final asset = opType == 'EXTERNAL' ? '203.0.113.${10 + i}' : '10.10.${i ~/ 5}.${10 + i}';
      return {
        'weakness_id': '$opId-w${i + 1}',
        'name': '$category - Debolezza #${i + 1}',
        'category': category,
        'severity': severity,
        'affected_asset': asset,
        'description':
            'Rilevata debolezza di categoria "$category" con severità $severity sull\'asset $asset.',
      };
    });
  }

  // --- MOCK DATA ---
  final List<Map<String, dynamic>> _mockPentests = [
    {
      'op_id': 'op-eu-7491',
      'name': 'Internal Active Directory Pentest',
      'state': 'COMPLETED',
      'op_type': 'INTERNAL',
      'launched_at': '2026-06-28T09:15:32Z',
      'completed_at': '2026-06-28T13:40:11Z',
      'weaknesses_count': 18,
    },
    {
      'op_id': 'op-eu-7522',
      'name': 'External Web App Perimeter Scan',
      'state': 'RUNNING',
      'op_type': 'EXTERNAL',
      'launched_at': '2026-07-01T11:00:00Z',
      'completed_at': null,
      'weaknesses_count': 3,
    },
    {
      'op_id': 'op-eu-7310',
      'name': 'PCI-DSS Compliance Assessment',
      'state': 'COMPLETED',
      'op_type': 'INTERNAL',
      'launched_at': '2026-06-15T08:00:00Z',
      'completed_at': '2026-06-15T15:22:45Z',
      'weaknesses_count': 32,
    },
    {
      'op_id': 'op-eu-7201',
      'name': 'Branch Office Network Audit',
      'state': 'FAILED',
      'op_type': 'INTERNAL',
      'launched_at': '2026-06-01T14:30:00Z',
      'completed_at': '2026-06-01T15:10:00Z',
      'weaknesses_count': 0,
    },
    {
      'op_id': 'op-eu-7590',
      'name': 'Scheduled Monthly Cloud Pentest',
      'state': 'QUEUED',
      'op_type': 'EXTERNAL',
      'launched_at': null,
      'completed_at': null,
      'weaknesses_count': 0,
    }
  ];

  final Map<String, Map<String, dynamic>> _mockPentestDetails = {
    'op-eu-7491': {
      'op_id': 'op-eu-7491',
      'name': 'Internal Active Directory Pentest',
      'state': 'COMPLETED',
      'op_type': 'INTERNAL',
      'launched_at': '2026-06-28T09:15:32Z',
      'completed_at': '2026-06-28T13:40:11Z',
      'weaknesses_count': 18,
      'credentials_count': 12,
      'cred_access_count': 5,
    },
    'op-eu-7522': {
      'op_id': 'op-eu-7522',
      'name': 'External Web App Perimeter Scan',
      'state': 'RUNNING',
      'op_type': 'EXTERNAL',
      'launched_at': '2026-07-01T11:00:00Z',
      'completed_at': null,
      'weaknesses_count': 3,
      'credentials_count': 0,
      'cred_access_count': 0,
    },
    'op-eu-7310': {
      'op_id': 'op-eu-7310',
      'name': 'PCI-DSS Compliance Assessment',
      'state': 'COMPLETED',
      'op_type': 'INTERNAL',
      'launched_at': '2026-06-15T08:00:00Z',
      'completed_at': '2026-06-15T15:22:45Z',
      'weaknesses_count': 32,
      'credentials_count': 24,
      'cred_access_count': 9,
    },
    'op-eu-7201': {
      'op_id': 'op-eu-7201',
      'name': 'Branch Office Network Audit',
      'state': 'FAILED',
      'op_type': 'INTERNAL',
      'launched_at': '2026-06-01T14:30:00Z',
      'completed_at': '2026-06-01T15:10:00Z',
      'weaknesses_count': 0,
      'credentials_count': 0,
      'cred_access_count': 0,
    },
    'op-eu-7590': {
      'op_id': 'op-eu-7590',
      'name': 'Scheduled Monthly Cloud Pentest',
      'state': 'QUEUED',
      'op_type': 'EXTERNAL',
      'launched_at': null,
      'completed_at': null,
      'weaknesses_count': 0,
      'credentials_count': 0,
      'cred_access_count': 0,
    }
  };

  final List<Map<String, dynamic>> _mockTemplates = [
    {
      'template_id': 'tpl-internal-ad',
      'name': 'Internal Active Directory Default',
      'description': 'Scansione interna completa del dominio Active Directory e subnet locali.',
      'op_type': 'INTERNAL',
    },
    {
      'template_id': 'tpl-external-perimeter',
      'name': 'External Perimeter Audit',
      'description': 'Audit esterno degli asset esposti su rete pubblica (IP/Domini).',
      'op_type': 'EXTERNAL',
    },
    {
      'template_id': 'tpl-pci-compliance',
      'name': 'PCI-DSS Vulnerability Scan',
      'description': 'Scansione di compliance focalizzata sul perimetro dei dati dei titolari di carta.',
      'op_type': 'INTERNAL',
    },
    {
      'template_id': 'tpl-ransomware-readiness',
      'name': 'Ransomware Readiness Drill',
      'description': 'Esercitazione per valutare la resilienza della rete ad attacchi di tipo Ransomware.',
      'op_type': 'INTERNAL',
    }
  ];
}
