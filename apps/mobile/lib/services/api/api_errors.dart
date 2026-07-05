import 'package:dio/dio.dart';

import '../subscription/subscription_provider.dart';

SubscriptionLimitException? subscriptionLimitFromError(Object error) {
  if (error is DioException && error.response?.statusCode == 402) {
    return SubscriptionLimitException.fromDio(error);
  }
  return null;
}

String apiErrorMessage(Object error) {
  final limit = subscriptionLimitFromError(error);
  if (limit != null) {
    return limit.userMessage;
  }

  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401) {
      return 'Your session expired. Please sign in again.';
    }
    if (status == 422) {
      return 'Some profile details are invalid. Please review and try again.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'The server took too long to respond. Check your connection and try again.';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'Could not reach the server. Check your internet connection.';
    }
    if (status != null && status >= 500) {
      return 'The server had a problem. Try again in a moment.';
    }
  }
  return 'Something went wrong. Check your connection and try again.';
}
