import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  String? _apiKey;
  String _region = 'EU';
  String? _token;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isMock = false;

  String? get apiKey => _apiKey;
  String get region => _region;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isMock => _isMock;
  bool get isAuthenticated => _token != null;

  // Initialize and check for stored credentials
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    _apiKey = await _storageService.getApiKey();
    _region = await _storageService.getRegion();

    if (_apiKey != null && _apiKey!.isNotEmpty) {
      await _autoAuthenticate();
    } else {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Attempt login with a new API Key and Region
  Future<bool> login(String key, String reg) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.authenticate(key, reg);

    if (result['success'] == true) {
      _apiKey = key;
      _region = reg;
      _token = result['token'];
      _isMock = result['isMock'] ?? false;
      _errorMessage = null;

      // Save to secure storage
      await _storageService.saveApiKey(key);
      await _storageService.saveRegion(reg);

      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['error'] ?? 'Authentication failed';
      _token = null;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Logout and clear credentials
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _storageService.deleteApiKey();
    _apiKey = null;
    _token = null;
    _errorMessage = null;
    _isMock = false;

    _isLoading = false;
    notifyListeners();
  }

  // Internal auto-authentication using stored credentials
  Future<void> _autoAuthenticate() async {
    if (_apiKey == null) return;
    
    final result = await _apiService.authenticate(_apiKey!, _region);

    if (result['success'] == true) {
      _token = result['token'];
      _isMock = result['isMock'] ?? false;
      _errorMessage = null;
    } else {
      // In case of error (e.g. key expired or network offline), don't wipe storage, just present error.
      _errorMessage = 'Auto-auth failed: ${result['error'] ?? "Unknown error"}';
      _token = null;
    }
    _isLoading = false;
    notifyListeners();
  }
}
