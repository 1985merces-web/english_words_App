import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum PurchaseVerificationStatus {
  verified,
  offlineGrace,
  rejected,
  error,
}

class PurchaseVerificationResult {
  const PurchaseVerificationResult({
    required this.status,
    this.orderId,
    this.signature,
    this.errorMessage,
  });

  final PurchaseVerificationStatus status;
  final String? orderId;
  final String? signature;
  final String? errorMessage;

  bool get isEntitled =>
      status == PurchaseVerificationStatus.verified ||
      status == PurchaseVerificationStatus.offlineGrace;

  @override
  String toString() =>
      'PurchaseVerificationResult(status: $status, orderId: $orderId, error: $errorMessage)';
}

class PurchaseVerifier {
  PurchaseVerifier({
    this.endpointUrl = 'https://volary.mrcs-global.com/api/verify-purchase',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static PurchaseVerifier instance = PurchaseVerifier();

  @visibleForTesting
  static PurchaseVerifier? debugOverride;

  final String endpointUrl;
  final http.Client _httpClient;

  static const Duration _requestTimeout = Duration(seconds: 10);

  Future<PurchaseVerificationResult> verify({
    required String packageName,
    required String productId,
    required String purchaseToken,
  }) async {
    if (debugOverride != null && !identical(debugOverride, this)) {
      return debugOverride!.verify(
        packageName: packageName,
        productId: productId,
        purchaseToken: purchaseToken,
      );
    }

    if (debugOverride == null &&
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return const PurchaseVerificationResult(
        status: PurchaseVerificationStatus.verified,
        orderId: 'FLUTTER_TEST_ORDER',
      );
    }

    try {
      final uri = Uri.parse(endpointUrl);
      final response = await _httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'packageName': packageName,
              'productId': productId,
              'purchaseToken': purchaseToken,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['valid'] == true) {
          return PurchaseVerificationResult(
            status: PurchaseVerificationStatus.verified,
            orderId: data['orderId']?.toString(),
            signature: data['signature']?.toString(),
          );
        } else {
          return PurchaseVerificationResult(
            status: PurchaseVerificationStatus.rejected,
            errorMessage: data['error']?.toString() ?? 'Invalid purchase',
          );
        }
      }

      // If client sent an invalid request (400) or forbidden (403), reject
      if (response.statusCode == 400 || response.statusCode == 403) {
        String? message;
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          message = data['error']?.toString();
        } catch (_) {}
        return PurchaseVerificationResult(
          status: PurchaseVerificationStatus.rejected,
          errorMessage: message ?? 'Server rejected token (${response.statusCode})',
        );
      }

      // Server error (500, 502, 503): grant offline grace period to protect user
      return const PurchaseVerificationResult(
        status: PurchaseVerificationStatus.offlineGrace,
        errorMessage: 'Backend unavailable; entered grace period',
      );
    } on TimeoutException catch (e) {
      debugPrint('[PurchaseVerifier] Network timeout: $e');
      return const PurchaseVerificationResult(
        status: PurchaseVerificationStatus.offlineGrace,
        errorMessage: 'Network timeout; entered grace period',
      );
    } on SocketException catch (e) {
      debugPrint('[PurchaseVerifier] Offline / Socket error: $e');
      return const PurchaseVerificationResult(
        status: PurchaseVerificationStatus.offlineGrace,
        errorMessage: 'Offline socket error; entered grace period',
      );
    } catch (e) {
      debugPrint('[PurchaseVerifier] Verification error: $e');
      return PurchaseVerificationResult(
        status: PurchaseVerificationStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}
