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
  // Nota: nello schema reale di Horizon3 il tipo `Pentest` NON espone un campo
  // `weaknesses` piatto. Le debolezze si leggono tramite il campo paginato
  // `weaknesses_page`, e ogni Weakness ha una struttura annidata:
  //   vuln { id name description } · affected_host { ip host_names os_names } · score · severity
  // Il parsing in fetchWeaknesses appiattisce questa struttura nella mappa
  // usata dal resto dell'app (weakness_id, name, severity, affected_asset, description).
  static const String getWeaknessesQuery = r'''
    query GetWeaknesses($op_id: String!, $page_input: PageInput) {
      pentest(op_id: $op_id) {
        weaknesses_page(page_input: $page_input) {
          weaknesses {
            vuln {
              id
              name
              description
            }
            affected_host {
              ip
              host_names
              os_names
            }
            score
            severity
          }
        }
      }
    }
  ''';

  // Variante ricca: tenta anche `category` (categoria della debolezza, es.
  // "Security Misconfiguration"). Se il tenant non espone quel campo, il fetch
  // ripiega su getWeaknessesQuery.
  static const String getWeaknessesRichQuery = r'''
    query GetWeaknesses($op_id: String!, $page_input: PageInput) {
      pentest(op_id: $op_id) {
        weaknesses_page(page_input: $page_input) {
          weaknesses {
            vuln {
              id
              name
              description
            }
            affected_host {
              ip
              host_names
              os_names
            }
            category
            score
            severity
          }
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

  // Mutation per lanciare un pentest EXTERNAL (ExternalAttack).
  // Lo scope è dato dagli asset già autorizzati nell'account: con
  // all_authorized_assets=true si testano tutti gli asset autorizzati; in
  // alternativa si può passare un asset_group_uuid specifico.
  static const String createExternalOpMutation = r'''
    mutation CreateExternalPentest($schedule_op_form: ScheduleOpFormInput!) {
      create_op(schedule_op_form: $schedule_op_form) {
        op {
          op_id
          op_name
          op_state
          op_type
          asset_group_uuid
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

    // 'category' non è esposto sul tipo Weakness (verificato via sonda): query singola.
    final variants = [getWeaknessesQuery];
    Object? lastError;

    try {
      for (var i = 0; i < variants.length; i++) {
        final isLast = i == variants.length - 1;
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'query': variants[i],
            'variables': {
              'op_id': opId,
              'page_input': {'page_num': 1, 'page_size': 500},
            },
          }),
        );

        if (response.statusCode != 200) {
          lastError = 'HTTP error ${response.statusCode}: ${response.reasonPhrase}';
          if (isLast) throw Exception(lastError);
          continue;
        }

        final body = jsonDecode(response.body);
        final data = body['data'];
        final page = data?['pentest']?['weaknesses_page'];
        final rawList = page?['weaknesses'];
        if (rawList is List) {
          return rawList
              .map<Map<String, dynamic>>((w) => _flattenWeakness(w as Map<String, dynamic>))
              .toList();
        }
        if (body['errors'] != null) {
          final errors = body['errors'] as List;
          final msg = errors.first['message']?.toString() ?? 'GraphQL Query Error';
          lastError = msg;
          final isFieldError = msg.contains('Cannot query field') ||
              msg.contains('must have a selection of subfields');
          if (!isLast && isFieldError) continue;
          throw Exception(msg);
        }
        if (isLast) return [];
      }
      throw Exception(lastError?.toString() ?? 'GraphQL Query Error');
    } catch (e) {
      print('fetchWeaknesses error: $e');
      rethrow;
    }
  }

  // Appiattisce una Weakness dello schema Horizon3 (vuln{...}, affected_host{...},
  // score, severity) nella mappa piatta usata da UI e ReportService:
  // weakness_id, name, category, severity, affected_asset, description, score.
  Map<String, dynamic> _flattenWeakness(Map<String, dynamic> w) {
    final vuln = w['vuln'] as Map<String, dynamic>?;
    final host = w['affected_host'] as Map<String, dynamic>?;

    String asset = '';
    if (host != null) {
      final names = host['host_names'];
      if (names is List && names.isNotEmpty) {
        asset = names.first.toString();
      } else if (host['ip'] != null) {
        asset = host['ip'].toString();
      }
    }

    return {
      'weakness_id': vuln?['id']?.toString() ?? '',
      'name': vuln?['name']?.toString() ?? 'Debolezza sconosciuta',
      // Categoria (dalla variante ricca); vuota se il tenant non la espone.
      'category': w['category']?.toString() ?? '',
      'severity': w['severity']?.toString() ?? '',
      'affected_asset': asset,
      'description': vuln?['description']?.toString() ?? '',
      'score': w['score'],
    };
  }

  // ===========================================================================
  // SEZIONI DEL PENTEST (Credentials, Hosts, Services, URLs, Users, Certificates)
  //
  // Ogni sezione del portale NodeZero corrisponde a un campo paginato annidato
  // dentro `pentest`, con lo stesso pattern delle weaknesses:
  //   pentest(op_id) { <sezione>_page(page_input) { <lista> { ...campi } } }
  //
  // I nomi esatti dei campi sono derivati dalla documentazione/portale Horizon3;
  // se il tenant espone nomi leggermente diversi, la query restituisce un errore
  // GraphQL isolato alla singola sezione (le altre continuano a funzionare) e il
  // messaggio "Cannot query field X ... did you mean Y" indica come correggerlo.
  // ===========================================================================

  // Helper generico: prova in ordine più varianti di query (dalla più "ricca"
  // di campi alla più "sicura"). Se una variante fallisce SOLO perché un campo
  // non esiste nello schema del tenant ("Cannot query field ..."), passa alla
  // successiva. Così possiamo tentare campi extra (categoria, prodotto, ecc.)
  // senza rischiare di rompere la sezione: nel peggiore dei casi si ripiega
  // sulla query minima garantita.
  Future<List<Map<String, dynamic>>> _fetchPentestSection({
    required String region,
    required String token,
    required String opId,
    required List<String> queries,
    required String pageField,
    required String listField,
    required Map<String, dynamic> Function(Map<String, dynamic>) flatten,
  }) async {
    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    Object? lastError;
    for (var i = 0; i < queries.length; i++) {
      final isLast = i == queries.length - 1;
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': queries[i],
          'variables': {
            'input': {'op_id': opId},
            'page_input': {'page_num': 1, 'page_size': 500},
          },
        }),
      );

      if (response.statusCode != 200) {
        lastError = 'HTTP error ${response.statusCode}: ${response.reasonPhrase}';
        if (isLast) throw Exception(lastError);
        continue;
      }

      final body = jsonDecode(response.body);
      final data = body['data'];
      final page = data?[pageField];
      final rawList = page?[listField];
      if (rawList is List) {
        return rawList
            .map<Map<String, dynamic>>((e) => flatten(e as Map<String, dynamic>))
            .toList();
      }
      if (body['errors'] != null) {
        final errors = body['errors'] as List;
        final msg = errors.first['message']?.toString() ?? 'GraphQL Query Error';
        lastError = msg;
        // Se è un errore di campo inesistente e ci sono ancora varianti, ripiega.
        final isFieldError = msg.contains('Cannot query field') ||
            msg.contains('must have a selection of subfields');
        if (!isLast && isFieldError) continue;
        throw Exception(msg);
      }
      // Nessun dato e nessun errore: prova la variante successiva se c'è.
      if (isLast) return [];
    }
    throw Exception(lastError?.toString() ?? 'GraphQL Query Error');
  }

  String _firstOf(dynamic list) {
    if (list is List && list.isNotEmpty) return list.first.toString();
    return '';
  }

  String _hostAsset(Map<String, dynamic>? host) {
    if (host == null) return '';
    final names = host['host_names'];
    if (names is List && names.isNotEmpty) return names.first.toString();
    if (host['ip'] != null) return host['ip'].toString();
    return '';
  }

  // --- Credentials ------------------------------------------------------------
  static const String getCredentialsQuery = r'''
    query GetCredentials($input: OpInput!, $page_input: PageInput) {
      credentials_page(input: $input, page_input: $page_input) {
        credentials {
          uuid
          user_name
          host_name
          role_name
          user_role
          score
          severity
          is_cracked
          cred_type
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchCredentials({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      return _generateMockCredentials(opId, count);
    }
    return _fetchPentestSection(
      region: region,
      token: token,
      opId: opId,
      queries: [getCredentialsQuery],
      pageField: 'credentials_page',
      listField: 'credentials',
      flatten: (c) {
        final roleParts = [c['role_name'], c['user_role']]
            .where((e) => e != null && e.toString().isNotEmpty)
            .map((e) => e.toString())
            .toList();
        return {
          'username': c['user_name']?.toString() ?? '',
          'severity': c['severity']?.toString() ?? '',
          'score': c['score'],
          'roles': roleParts.join(' / '),
          'asset': c['host_name']?.toString() ?? '',
          'cracked': (c['is_cracked'] == true) ? 'Sì' : 'No',
          'service_type': c['cred_type']?.toString() ?? '',
        };
      },
    );
  }

  // --- Hosts ------------------------------------------------------------------
  static const String getHostsQuery = r'''
    query GetHosts($input: OpInput!, $page_input: PageInput) {
      hosts_page(input: $input, page_input: $page_input) {
        hosts {
          uuid
          ip
          host_names
          os_names
          severity
          score
          weaknesses_count
          services_count
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchHosts({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      return _generateMockHosts(opId, count);
    }
    return _fetchPentestSection(
      region: region,
      token: token,
      opId: opId,
      queries: [getHostsQuery],
      pageField: 'hosts_page',
      listField: 'hosts',
      flatten: (h) => {
        'ip': h['ip']?.toString() ?? '',
        'hostname': _firstOf(h['host_names']),
        'os': _firstOf(h['os_names']),
        'severity': h['severity']?.toString() ?? '',
        'score': h['score'],
        'weakness_count': h['weaknesses_count']?.toString() ?? '0',
        'service_count': h['services_count']?.toString() ?? '0',
      },
    );
  }

  // --- Services (campi confermati dallo schema via sonda) ---------------------
  static const String getServicesQuery = r'''
    query GetServices($input: OpInput!, $page_input: PageInput) {
      services_page(input: $input, page_input: $page_input) {
        services {
          uuid
          port
          protocol
          product
          ip
          host_name
          severity
          score
          weaknesses_count
          credentials_count
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchServices({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      return _generateMockServices(opId, count);
    }
    return _fetchPentestSection(
      region: region,
      token: token,
      opId: opId,
      queries: [getServicesQuery],
      pageField: 'services_page',
      listField: 'services',
      flatten: (s) => {
        'host': (s['host_name']?.toString().isNotEmpty ?? false)
            ? s['host_name'].toString()
            : (s['ip']?.toString() ?? ''),
        'type': s['protocol']?.toString() ?? '',
        'port': s['port']?.toString() ?? '',
        'product': s['product']?.toString() ?? '',
        'severity': s['severity']?.toString() ?? '',
        'score': s['score'],
        'weakness_count': s['weaknesses_count']?.toString() ?? '0',
        'credential_count': s['credentials_count']?.toString() ?? '0',
      },
    );
  }

  // --- URLs -------------------------------------------------------------------
  static const String getUrlsQuery = r'''
    query GetUrls($input: OpInput!, $page_input: PageInput) {
      urls_page(input: $input, page_input: $page_input) {
        urls {
          uuid
          url
          severity
          score
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchUrls({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      return _generateMockUrls(opId, count);
    }
    return _fetchPentestSection(
      region: region,
      token: token,
      opId: opId,
      queries: [getUrlsQuery],
      pageField: 'urls_page',
      listField: 'urls',
      flatten: (u) => {
        'website': u['url']?.toString() ?? '',
        'host': _hostAsset(u['affected_host'] as Map<String, dynamic>?),
        'port': u['port']?.toString() ?? '',
        'product': u['product']?.toString() ?? '',
        'severity': u['severity']?.toString() ?? '',
        'score': u['score'],
      },
    );
  }

  // --- Users ------------------------------------------------------------------
  static const String getUsersQuery = r'''
    query GetUsers($input: OpInput!, $page_input: PageInput) {
      users_page(input: $input, page_input: $page_input) {
        users {
          uuid
          name
          domain_name
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchUsers({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      return _generateMockUsers(opId, count);
    }
    return _fetchPentestSection(
      region: region,
      token: token,
      opId: opId,
      queries: [getUsersQuery],
      pageField: 'users_page',
      listField: 'users',
      flatten: (u) => {
        'username': u['name']?.toString() ?? '',
        'domain_name': u['domain_name']?.toString() ?? '',
        // Campi non esposti come scalari dallo schema User via API key.
        'service': '',
        'compromised': '',
        'source': '',
        'host': '',
      },
    );
  }

  // --- Certificates -----------------------------------------------------------
  static const String getCertificatesQuery = r'''
    query GetCertificates($input: OpInput!, $page_input: PageInput) {
      certificates_page(input: $input, page_input: $page_input) {
        certificates {
          uuid
        }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchCertificates({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      return _generateMockCertificates(opId, count);
    }
    return _fetchPentestSection(
      region: region,
      token: token,
      opId: opId,
      queries: [getCertificatesQuery],
      pageField: 'certificates_page',
      listField: 'certificates',
      flatten: (c) => {
        'host': _hostAsset(c['affected_host'] as Map<String, dynamic>?),
        'subject': c['subject']?.toString() ?? '',
        'issuer': c['issuer']?.toString() ?? '',
        'not_after': c['not_after']?.toString() ?? '',
      },
    );
  }

  // --- URLs / Web Routes ------------------------------------------------------
  // NB: web_routes_page prende `op_id: String!` (NON `input: OpInput`).
  // Il tipo WebRoute espone solo url/host (via sonda).
  // `host` potrebbe essere scalare oppure un oggetto: proviamo entrambe le
  // forme, con fallback finale al solo url (campo sicuramente valido).
  static const String getWebRoutesHostObjQuery = r'''
    query GetWebRoutes($op_id: String!, $page_input: PageInput) {
      web_routes_page(op_id: $op_id, page_input: $page_input) {
        web_routes { uuid url host { ip host_names } }
      }
    }
  ''';

  static const String getWebRoutesQuery = r'''
    query GetWebRoutes($op_id: String!, $page_input: PageInput) {
      web_routes_page(op_id: $op_id, page_input: $page_input) {
        web_routes { uuid url host }
      }
    }
  ''';

  static const String getWebRoutesMinQuery = r'''
    query GetWebRoutes($op_id: String!, $page_input: PageInput) {
      web_routes_page(op_id: $op_id, page_input: $page_input) {
        web_routes { uuid url }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchWebRoutes({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      final detail = _mockPentestDetails[opId];
      final count = detail?['weaknesses_count'] as int? ?? 0;
      return _generateMockUrls(opId, count);
    }
    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    final variants = [
      getWebRoutesHostObjQuery,
      getWebRoutesQuery,
      getWebRoutesMinQuery,
    ];
    Object? lastError;

    for (var i = 0; i < variants.length; i++) {
      final isLast = i == variants.length - 1;
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': variants[i],
          'variables': {
            'op_id': opId,
            'page_input': {'page_num': 1, 'page_size': 500},
          },
        }),
      );

      if (response.statusCode != 200) {
        lastError = 'HTTP error ${response.statusCode}: ${response.reasonPhrase}';
        if (isLast) throw Exception(lastError);
        continue;
      }

      final body = jsonDecode(response.body);
      final rawList = body['data']?['web_routes_page']?['web_routes'];
      if (rawList is List) {
        return rawList.map<Map<String, dynamic>>((w) {
          final m = w as Map<String, dynamic>;
          final h = m['host'];
          String hostStr = '';
          if (h is Map) {
            final names = h['host_names'];
            if (names is List && names.isNotEmpty) {
              hostStr = names.first.toString();
            } else if (h['ip'] != null) {
              hostStr = h['ip'].toString();
            }
          } else if (h != null) {
            hostStr = h.toString();
          }
          return {
            'website': m['url']?.toString() ?? '',
            'host': hostStr,
          };
        }).toList();
      }
      if (body['errors'] != null) {
        final errs = body['errors'] as List;
        final msg = errs.first['message']?.toString() ?? 'GraphQL Query Error';
        lastError = msg;
        // Ripiega sulla variante successiva sia per errori di campo, sia per
        // l'errore generico del gateway ("unexpected error / investigating"),
        // che alcune query/campi fanno scattare lato server.
        final retryable = msg.contains('Cannot query field') ||
            msg.contains('must have a selection of subfields') ||
            msg.contains('must not have a selection') ||
            msg.toLowerCase().contains('unexpected error') ||
            msg.toLowerCase().contains('investigating');
        if (!isLast && retryable) continue;
        throw Exception(msg);
      }
      if (isLast) return [];
    }
    throw Exception(lastError?.toString() ?? 'GraphQL Query Error');
  }

  // --- Data / Data Stores -----------------------------------------------------
  static const String getDataStoresQuery = r'''
    query GetDataStores($input: OpInput!, $page_input: PageInput) {
      data_stores_page(input: $input, page_input: $page_input) {
        data_stores { uuid name host_name ip severity score }
      }
    }
  ''';

  Future<List<Map<String, dynamic>>> fetchDataStores({
    required String apiKey,
    required String region,
    required String token,
    required String opId,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 400));
      return [];
    }
    return _fetchPentestSection(
      region: region,
      token: token,
      opId: opId,
      queries: [getDataStoresQuery],
      pageField: 'data_stores_page',
      listField: 'data_stores',
      flatten: (d) => {
        'name': d['name']?.toString() ?? '',
        'host': (d['host_name']?.toString().isNotEmpty ?? false)
            ? d['host_name'].toString()
            : (d['ip']?.toString() ?? ''),
        'severity': d['severity']?.toString() ?? '',
        'score': d['score'],
      },
    );
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

  // TEMP: "sonda di campi". L'introspezione __type è disabilitata sul gateway,
  // quindi chiediamo tanti campi candidati su ogni tipo in UNA query. GraphQL
  // valida tutto e restituisce, per ogni campo inesistente, un errore con il
  // suggerimento "did you mean ...": da lì ricaviamo i nomi reali dei campi.
  // I campi che NON compaiono negli errori sono validi (esistono).
  // Sonda 2: SCOPERTA di query/sezioni e campi riassuntivi ancora mancanti.
  // - Testa quali query di lista esistono (URLs/EDR/Subdomains/Data/Websites):
  //   se non esistono danno "Cannot query field ... on type 'Query'".
  // - Testa campi riassuntivi sul tipo Pentest (exposure, conteggi).
  // Sonda 4: dump della RISPOSTA GREZZA di web_routes_page (per capire perché
  // torna vuoto) provando due firme: op_id e input.
  static const String _fieldProbeQuery = r'''
    query RawProbe($op_id: String!, $page_input: PageInput) {
      web_routes_page(op_id: $op_id, page_input: $page_input) {
        web_routes { uuid url host }
      }
    }
  ''';

  Future<String> dumpSectionsSchema({
    required String region,
    required String token,
    required String opId,
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
        body: jsonEncode({
          'query': _fieldProbeQuery,
          'variables': {
            'op_id': opId,
            'input': {'op_id': opId},
            'page_input': {'page_num': 1, 'page_size': 1},
          },
        }),
      );
      return 'HTTP ${response.statusCode}\n${response.body}';
    } catch (e) {
      return 'Field probe request failed: $e';
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

  // Lancia un pentest EXTERNAL (op_type: ExternalAttack). Lo scope arriva dagli
  // asset già autorizzati nell'account: se assetGroupUuid è null si usa
  // all_authorized_assets=true (tutti gli asset autorizzati), altrimenti si
  // targetizza lo specifico asset group. Non richiede runner/Docker: NodeZero
  // gira dal cloud di Horizon3.
  Future<Map<String, dynamic>> launchExternalPentest({
    required String apiKey,
    required String region,
    required String token,
    required String opName,
    String? assetGroupUuid,
  }) async {
    if (_isMockKey(apiKey)) {
      await Future.delayed(const Duration(milliseconds: 1500));
      final newOpId = 'op-ext-${_mockPentests.length + 8100}';
      final newOp = {
        'op_id': newOpId,
        'name': opName,
        'state': 'QUEUED',
        'op_type': 'EXTERNAL',
        'launched_at': null,
        'completed_at': null,
        'weaknesses_count': 0,
        'targets': const <String>[],
      };
      _mockPentests.insert(0, newOp);
      _mockPentestDetails[newOpId] = {
        ...newOp,
        'credentials_count': 0,
        'cred_access_count': 0,
      };
      _simulateMockScanProgress(newOpId, 'EXTERNAL');
      return {'success': true, 'op_id': newOpId, 'name': opName};
    }

    final baseUrl = _getBaseUrl(region);
    final url = Uri.parse('$baseUrl/graphql');

    // Costruisce lo schedule_op_form external.
    final Map<String, dynamic> scheduleForm = {
      'op_name': opName,
      'op_type': 'ExternalAttack',
    };
    if (assetGroupUuid != null && assetGroupUuid.trim().isNotEmpty) {
      scheduleForm['asset_group_uuid'] = assetGroupUuid.trim();
    } else {
      scheduleForm['all_authorized_assets'] = true;
    }

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'query': createExternalOpMutation,
          'variables': {'schedule_op_form': scheduleForm},
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
            'name': op['op_name'] ?? op['name'] ?? opName,
          };
        }
        if (body['errors'] != null) {
          final errors = body['errors'] as List;
          return {
            'success': false,
            'error': errors.first['message'] ?? 'GraphQL Mutation Error',
          };
        }
        return {'success': false, 'error': 'Response format unexpected'};
      } else {
        print('launchExternalPentest HTTP ${response.statusCode} body: ${response.body}');
        return {
          'success': false,
          'error': 'HTTP error ${response.statusCode}: ${_parseError(response.body)}',
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
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

  // Generatori mock per le sezioni: dimensione derivata deterministicamente dal
  // numero di debolezze, così una scansione mock "completata" mostra dati
  // coerenti in tutte le schede.
  List<Map<String, dynamic>> _generateMockCredentials(String opId, int wCount) {
    final count = wCount == 0 ? 0 : ((wCount / 3).ceil()).clamp(1, 12);
    const severities = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];
    const services = ['SSH', 'SMB', 'RDP', 'TCPWRAPPED'];
    return List.generate(count, (i) => {
          'username': i == 0 ? 'admin' : 'user${i + 1}',
          'severity': severities[i % severities.length],
          'score': 9 - (i % 4) * 2,
          'cracked': i.isEven ? 'Sì' : 'No',
          'roles': i == 0 ? 'Local User' : 'Domain User',
          'service_type': services[i % services.length],
          'asset': '172.16.1.${250 + (i % 6)}',
        });
  }

  List<Map<String, dynamic>> _generateMockHosts(String opId, int wCount) {
    final count = wCount == 0 ? 0 : (wCount + 2).clamp(1, 24);
    const severities = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];
    const oss = ['Windows', 'Windows Server', 'Linux'];
    const access = ['Anonymous', 'Local User', 'Admin'];
    return List.generate(count, (i) => {
          'ip': '172.16.1.${10 + i}',
          'hostname': 'host-${10 + i}',
          'os': oss[i % oss.length],
          'severity': severities[i % severities.length],
          'score': 8 - (i % 4) * 2,
          'access_level': access[i % access.length],
          'weakness_count': (i % 3).toString(),
        });
  }

  List<Map<String, dynamic>> _generateMockServices(String opId, int wCount) {
    final count = wCount == 0 ? 0 : (wCount * 2).clamp(1, 40);
    const types = ['ssh', 'http', 'smb', 'rdp', 'ftp'];
    const products = ['OpenSSH 8.2', 'Apache 2.4.66', 'Samba 4.13', 'MS RDP', 'vsftpd 3.0'];
    const severities = ['HIGH', 'MEDIUM', 'LOW', 'INFO'];
    return List.generate(count, (i) => {
          'host': '172.16.1.${10 + (i % 12)}',
          'type': types[i % types.length],
          'port': [22, 80, 445, 3389, 21][i % 5].toString(),
          'product': products[i % products.length],
          'severity': severities[i % severities.length],
          'score': (i % 5).toString(),
          'weakness_count': (i % 2).toString(),
          'credential_count': (i % 3).toString(),
        });
  }

  List<Map<String, dynamic>> _generateMockUrls(String opId, int wCount) {
    final count = wCount == 0 ? 0 : 1;
    return List.generate(count, (i) => {
          'website': 'http://172.16.1.${79 + i}',
          'host': '172.16.1.${79 + i}',
          'port': '80',
          'product': 'Apache HTTPD 2.4.66',
          'severity': 'INFO',
          'score': '0',
        });
  }

  List<Map<String, dynamic>> _generateMockUsers(String opId, int wCount) {
    final count = wCount == 0 ? 0 : ((wCount / 3).ceil()).clamp(1, 8);
    return List.generate(count, (i) => {
          'username': i == 0 ? 'admin' : 'user${i + 1}',
          'compromised': i.isEven ? 'Sì' : 'No',
          'source': 'Default Login',
          'host': '172.16.1.${252 + (i % 4)}',
          'domain_name': 'TESYSGROUP.LOCAL',
        });
  }

  List<Map<String, dynamic>> _generateMockCertificates(String opId, int wCount) {
    final count = wCount == 0 ? 0 : 1;
    return List.generate(count, (i) => {
          'host': '172.16.1.${79 + i}',
          'subject': 'CN=172.16.1.${79 + i}',
          'issuer': 'CN=NodeZero Test CA',
          'not_after': '2027-01-01T00:00:00Z',
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
