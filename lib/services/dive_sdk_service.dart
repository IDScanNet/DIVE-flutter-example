import 'dart:async';
import 'package:flutter/services.dart';
import '../models/dive_result.dart';

/// Service for communicating with native DIVE SDK implementations
class DiveSDKService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.dive_demo_usage/dive_sdk',
  );

  static const EventChannel _uploadProgressChannel = EventChannel(
    'com.example.dive_demo_usage/dive_sdk/upload_progress',
  );

  // StreamController to manage native EventChannel subscription
  static StreamController<double>? _progressController;
  static StreamSubscription? _nativeSubscription;
  static int _listenerCount = 0;

  /// Get stream of upload progress events
  /// Returns a stream of double values from 0.0 to 1.0 representing upload progress
  /// Uses a shared StreamController to avoid multiple native subscriptions
  static Stream<double> get uploadProgressStream {
    // Create controller only if it doesn't exist yet
    _progressController ??= StreamController<double>.broadcast(
      onListen: _startNativeSubscription,
      onCancel: _stopNativeSubscription,
    );

    return _progressController!.stream;
  }

  /// Starts native subscription when first listener is added
  static void _startNativeSubscription() {
    _listenerCount++;

    // Create subscription only if it doesn't exist
    if (_nativeSubscription == null) {
      _nativeSubscription = _uploadProgressChannel
          .receiveBroadcastStream()
          .map((event) {
            if (event is num) {
              return event.toDouble();
            }
            return 0.0;
          })
          .listen(
            (progress) {
              _progressController?.add(progress);
            },
            onError: (error) {
              _progressController?.addError(error);
            },
            onDone: () {
              // When native stream completes, clear subscription
              _nativeSubscription = null;
            },
          );
    }
  }

  /// Stops native subscription when all listeners have canceled
  static void _stopNativeSubscription() {
    _listenerCount--;

    // Cancel native subscription only when all listeners are gone
    if (_listenerCount <= 0) {
      _listenerCount = 0;
      _nativeSubscription?.cancel();
      _nativeSubscription = null;
    }
  }

  /// Clears all resources (call when you need a complete reset)
  static void dispose() {
    _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _progressController?.close();
    _progressController = null;
    _listenerCount = 0;
  }

  /// Launch the native DIVE SDK for document scanning
  ///
  /// [token] - API authorization token for DIVE server
  /// [licenseKey] - License key for SDK configuration
  ///
  /// Returns a [DiveResult] indicating success, error, or cancellation
  static Future<DiveResult> launchDive({
    required String token,
    required String licenseKey,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'launchDive',
        {'token': token, 'licenseKey': licenseKey},
      );

      return _parseResult(result);
    } on PlatformException catch (e) {
      // Handle platform-specific exceptions
      return DiveError(
        code: e.code,
        message: e.message ?? 'Platform error occurred',
      );
    } catch (e) {
      // Handle any other exceptions
      return DiveError(code: 'UNEXPECTED_ERROR', message: e.toString());
    }
  }

  /// Launch the native DIVE Online SDK for document scanning
  ///
  /// [token] - API authorization token for DIVE Online server
  /// [integrationId] - Integration ID for DIVE Online SDK
  /// [baseUrl] - Base URL for DIVE Online API
  /// [firstName] - Applicant first name
  /// [lastName] - Applicant last name
  /// [phone] - Applicant phone number
  ///
  /// Returns a [DiveResult] indicating success, error, or cancellation
  static Future<DiveResult> launchDiveOnline({
    required String token,
    required String integrationId,
    required String baseUrl,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('launchDiveOnline', {
            'token': token,
            'integrationId': integrationId,
            'baseUrl': baseUrl,
            'firstName': firstName,
            'lastName': lastName,
            'phone': phone,
          });

      return _parseResult(result);
    } on PlatformException catch (e) {
      // Handle platform-specific exceptions
      return DiveError(
        code: e.code,
        message: e.message ?? 'Platform error occurred',
      );
    } catch (e) {
      // Handle any other exceptions
      return DiveError(code: 'UNEXPECTED_ERROR', message: e.toString());
    }
  }

  /// Convert Map with Object keys to Map with String keys
  static Map<String, dynamic> _convertToStringMap(Map<Object?, Object?> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final stringKey = key.toString();
      if (value is Map<Object?, Object?>) {
        result[stringKey] = _convertToStringMap(value);
      } else if (value is List) {
        result[stringKey] = _convertList(value);
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }

  /// Convert List to List with proper type conversion
  static List<dynamic> _convertList(List list) {
    return list.map((item) {
      if (item is Map<Object?, Object?>) {
        return _convertToStringMap(item);
      } else if (item is List) {
        return _convertList(item);
      } else {
        return item;
      }
    }).toList();
  }

  /// Parse the result from native platform
  static DiveResult _parseResult(Map<Object?, Object?>? result) {
    if (result == null) {
      return const DiveError(
        code: 'NULL_RESULT',
        message: 'No result received from native SDK',
      );
    }

    // Check if success
    final success = result['success'] as bool?;
    if (success == true) {
      final requestKey = result['requestKey'] as String? ?? '';
      final fullResult = result['fullResult'] as Map<Object?, Object?>?;

      // Convert fullResult to Map<String, dynamic>
      Map<String, dynamic>? fullResultMap;
      if (fullResult != null) {
        fullResultMap = _convertToStringMap(fullResult);
      }

      // Debug: print results in console (for development only)
      // ignore: avoid_print
      print('DIVE SDK Result: $result');

      // Always return success if fullResult exists (iOS doesn't have requestKey)
      if (fullResultMap != null) {
        return DiveSuccess(requestKey: requestKey, fullResult: fullResultMap);
      } else if (requestKey.isNotEmpty) {
        return DiveSuccess(requestKey: requestKey, fullResult: null);
      } else {
        return const DiveError(
          code: 'MISSING_DATA',
          message: 'No result data received from SDK',
        );
      }
    }

    // Check if cancelled
    final cancelled = result['cancelled'] as bool?;
    if (cancelled == true) {
      return const DiveCancelled();
    }

    // Check for error
    final error = result['error'] as String?;
    final errorCode = result['errorCode'] as String? ?? 'UNKNOWN_ERROR';
    if (error != null) {
      return DiveError(code: errorCode, message: error);
    }

    return const DiveError(
      code: 'INVALID_RESULT',
      message: 'Invalid result format from native SDK',
    );
  }
}
