import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _keyApiKey = 'h3_api_key';
  static const String _keyRegion = 'h3_region';

  // Read API Key
  Future<String?> getApiKey() async {
    try {
      return await _secureStorage.read(key: _keyApiKey);
    } catch (e) {
      // Fallback in case of desktop platform issues (e.g., missing keyring)
      print('Secure storage read failed: $e');
      return null;
    }
  }

  // Write API Key
  Future<void> saveApiKey(String apiKey) async {
    try {
      await _secureStorage.write(key: _keyApiKey, value: apiKey);
    } catch (e) {
      print('Secure storage write failed: $e');
    }
  }

  // Delete API Key (Logout)
  Future<void> deleteApiKey() async {
    try {
      await _secureStorage.delete(key: _keyApiKey);
    } catch (e) {
      print('Secure storage delete failed: $e');
    }
  }

  // Read Region (US or EU, default to EU as requested)
  Future<String> getRegion() async {
    try {
      final region = await _secureStorage.read(key: _keyRegion);
      return region ?? 'EU';
    } catch (e) {
      print('Secure storage read region failed: $e');
      return 'EU';
    }
  }

  // Write Region
  Future<void> saveRegion(String region) async {
    try {
      await _secureStorage.write(key: _keyRegion, value: region);
    } catch (e) {
      print('Secure storage write region failed: $e');
    }
  }
}
