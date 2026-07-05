class ApiConstants {
  /// Local API server (see infra/docker-compose.yml + services/api).
  /// Override: flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}

