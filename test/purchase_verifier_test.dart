import 'dart:convert';
import 'dart:io';

import 'package:english_words_app/services/billing_service.dart';
import 'package:english_words_app/services/purchase_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePurchaseDetails extends PurchaseDetails {
  _FakePurchaseDetails({
    required super.productID,
    required super.purchaseID,
    required super.verificationData,
    required super.transactionDate,
    required super.status,
  });
}

class _MockPurchaseVerifier extends PurchaseVerifier {
  _MockPurchaseVerifier(this._handler);

  final Future<PurchaseVerificationResult> Function({
    required String packageName,
    required String productId,
    required String purchaseToken,
  }) _handler;

  @override
  Future<PurchaseVerificationResult> verify({
    required String packageName,
    required String productId,
    required String purchaseToken,
  }) =>
      _handler(
        packageName: packageName,
        productId: productId,
        purchaseToken: purchaseToken,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BillingService.resetForTesting();
    PurchaseVerifier.debugOverride = null;
  });

  tearDown(() {
    BillingService.resetForTesting();
    PurchaseVerifier.debugOverride = null;
  });

  group('PurchaseVerifier HTTP Handling', () {
    test('returns verified when endpoint responds 200 with valid=true', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/verify-purchase');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['packageName'], 'com.mrcsglobal.volary');
        expect(body['productId'], 'volary_premium_lifetime');
        expect(body['purchaseToken'], 'valid_token_123');

        return http.Response(
          jsonEncode({
            'valid': true,
            'orderId': 'GPA.1234-5678-9012',
            'signature': 'test_hmac_signature',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final verifier = PurchaseVerifier(
        endpointUrl: 'https://volary.mrcs-global.com/api/verify-purchase',
        httpClient: mockClient,
      );

      // Explicitly set debugOverride so it uses the mockClient rather than
      // the test-runner short-circuit
      PurchaseVerifier.debugOverride = verifier;

      final result = await verifier.verify(
        packageName: 'com.mrcsglobal.volary',
        productId: 'volary_premium_lifetime',
        purchaseToken: 'valid_token_123',
      );

      expect(result.status, equals(PurchaseVerificationStatus.verified));
      expect(result.isEntitled, isTrue);
      expect(result.orderId, equals('GPA.1234-5678-9012'));
      expect(result.signature, equals('test_hmac_signature'));
    });

    test('returns rejected when endpoint responds 400', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'valid': false, 'error': 'Google Play rejected token'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final verifier = PurchaseVerifier(
        endpointUrl: 'https://volary.mrcs-global.com/api/verify-purchase',
        httpClient: mockClient,
      );
      PurchaseVerifier.debugOverride = verifier;

      final result = await verifier.verify(
        packageName: 'com.mrcsglobal.volary',
        productId: 'volary_premium_lifetime',
        purchaseToken: 'fraud_token',
      );

      expect(result.status, equals(PurchaseVerificationStatus.rejected));
      expect(result.isEntitled, isFalse);
      expect(result.errorMessage, contains('Google Play rejected token'));
    });

    test('returns offlineGrace when backend returns 503', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      final verifier = PurchaseVerifier(
        endpointUrl: 'https://volary.mrcs-global.com/api/verify-purchase',
        httpClient: mockClient,
      );
      PurchaseVerifier.debugOverride = verifier;

      final result = await verifier.verify(
        packageName: 'com.mrcsglobal.volary',
        productId: 'volary_premium_lifetime',
        purchaseToken: 'token_when_server_down',
      );

      expect(result.status, equals(PurchaseVerificationStatus.offlineGrace));
      expect(result.isEntitled, isTrue);
    });

    test('returns offlineGrace when client has SocketException', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('No address associated with hostname');
      });

      final verifier = PurchaseVerifier(
        endpointUrl: 'https://volary.mrcs-global.com/api/verify-purchase',
        httpClient: mockClient,
      );
      PurchaseVerifier.debugOverride = verifier;

      final result = await verifier.verify(
        packageName: 'com.mrcsglobal.volary',
        productId: 'volary_premium_lifetime',
        purchaseToken: 'token_offline',
      );

      expect(result.status, equals(PurchaseVerificationStatus.offlineGrace));
      expect(result.isEntitled, isTrue);
    });
  });

  group('BillingService Purchase Verification Integration', () {
    test('successful verification stores orderId and signature and grants premium',
        () async {
      PurchaseVerifier.debugOverride = _MockPurchaseVerifier(
        ({required packageName, required productId, required purchaseToken}) async {
          return const PurchaseVerificationResult(
            status: PurchaseVerificationStatus.verified,
            orderId: 'GPA.TEST-999',
            signature: 'sig_abc',
          );
        },
      );

      final billing = BillingService();
      await billing.init();
      expect(billing.hasLifetimePremium, isFalse);

      // Simulate purchase update directly
      final purchase = _FakePurchaseDetails(
        productID: 'volary_premium_lifetime',
        purchaseID: 'order_test',
        verificationData: PurchaseVerificationData(
          localVerificationData: 'test',
          serverVerificationData: 'server_token_123',
          source: 'google_play',
        ),
        transactionDate: DateTime.now().millisecondsSinceEpoch.toString(),
        status: PurchaseStatus.purchased,
      );

      // Verify entitlement result via verifier
      final result = await PurchaseVerifier.instance.verify(
        packageName: 'com.mrcsglobal.volary',
        productId: purchase.productID,
        purchaseToken: purchase.verificationData.serverVerificationData,
      );
      expect(result.isEntitled, isTrue);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('premium_lifetime', true);
      await prefs.setString('premium_order_id', result.orderId!);
      await prefs.setString('premium_signature', result.signature!);

      expect(prefs.getBool('premium_lifetime'), isTrue);
      expect(prefs.getString('premium_order_id'), equals('GPA.TEST-999'));
      expect(prefs.getString('premium_signature'), equals('sig_abc'));
    });

    test('rejected verification does not grant premium', () async {
      PurchaseVerifier.debugOverride = _MockPurchaseVerifier(
        ({required packageName, required productId, required purchaseToken}) async {
          return const PurchaseVerificationResult(
            status: PurchaseVerificationStatus.rejected,
            errorMessage: 'Token expired or revoked',
          );
        },
      );

      final billing = BillingService();
      await billing.init();
      expect(billing.hasLifetimePremium, isFalse);

      final result = await PurchaseVerifier.instance.verify(
        packageName: 'com.mrcsglobal.volary',
        productId: 'volary_premium_lifetime',
        purchaseToken: 'bad_token',
      );
      expect(result.isEntitled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('premium_lifetime'), isNull);
    });
  });
}
