import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/router/router_refresh.dart';
import '../storage/token_storage.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = TokenStorage.token;
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      if (error.response?.statusCode == 401) {
        await TokenStorage.clear();
        RouterRefresh.instance.refresh();
      }
      handler.next(error);
    },
  ));

  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> register(String email, String password, String displayName) async {
    final res = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'display_name': displayName,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getProfile() async {
    final res = await _dio.get('/users/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await _dio.patch('/users/me', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>?> getActiveWorkoutPlan() async {
    final res = await _dio.get('/plans/workout/active');
    if (res.data == null) return null;
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> generateWorkoutPlan() async {
    final res = await _dio.post('/plans/workout/generate');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>?> getActiveNutritionPlan() async {
    final res = await _dio.get('/plans/nutrition/active');
    if (res.data == null) return null;
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> generateNutritionPlan() async {
    final res = await _dio.post('/plans/nutrition/generate');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getProgressSummary() async {
    final res = await _dio.get('/progress/summary');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getGamificationState() async {
    final res = await _dio.get('/gamification/state');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> logWorkout(Map<String, dynamic> data) async {
    final res = await _dio.post('/logs/workout', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> logFood(Map<String, dynamic> data) async {
    final res = await _dio.post('/logs/food', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> analyzeFood(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post('/vision/food/analyze', data: formData);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadFormSession(Map<String, dynamic> data) async {
    final res = await _dio.post('/vision/form/session', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> fetchCoachSpeech(String text) async {
    final res = await _dio.post('/vision/coach/speak', data: {'text': text});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getSubscriptionPlans() async {
    final res = await _dio.get('/subscriptions/plans');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    final res = await _dio.get('/subscriptions/status');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> activateSubscription(String productId) async {
    final res = await _dio.post('/subscriptions/activate', data: {'product_id': productId});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createHabit(String name) async {
    final res = await _dio.post('/gamification/habits', data: {'name': name});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> checkHabit(String habitId) async {
    final res = await _dio.post('/gamification/habits/$habitId/check');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Stream<String> chatStream(String message, {String? threadId}) async* {
    final response = await _dio.post<ResponseBody>(
      '/chat/stream',
      data: {'message': message, if (threadId != null) 'thread_id': threadId},
      options: Options(responseType: ResponseType.stream, headers: {'Accept': 'text/event-stream'}),
    );

    final stream = response.data?.stream;
    if (stream == null) return;

    String buffer = '';
    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk).replaceAll('\r\n', '\n');
      while (buffer.contains('\n\n')) {
        final idx = buffer.indexOf('\n\n');
        final eventBlock = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        yield eventBlock;
      }
    }
    if (buffer.trim().isNotEmpty) {
      yield buffer;
    }
  }
}
