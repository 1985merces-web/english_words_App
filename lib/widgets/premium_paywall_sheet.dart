import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/billing_service.dart';

enum PaywallText {
  title,
  trialActive,
  featureLocked,
  benefitAdFree,
  benefitReader,
  benefitAutoplay,
  trialFooter,
  buyLifetime,
  productUnavailable,
  restore,
  oneTimePayment,
  actionStartedPurchase,
  actionStartedRestore,
  storeUnavailable,
  productNotConfigured,
  actionFailed,
}

class PremiumPaywallSheet extends StatefulWidget {
  const PremiumPaywallSheet({
    super.key,
    required this.featureName,
    this.languageCode,
  });

  final String featureName;
  final String? languageCode;

  @override
  State<PremiumPaywallSheet> createState() => _PremiumPaywallSheetState();
}

class _PremiumPaywallSheetState extends State<PremiumPaywallSheet> {
  final BillingService _billing = BillingService();
  ProductDetails? _product;
  bool _isLoading = true;
  bool _isSubmitting = false;

  static const Map<String, Map<PaywallText, String>> _translations = {
    'en': {
      PaywallText.title: 'Volary Premium',
      PaywallText.trialActive: 'Premium is active for another ~{hours} h.',
      PaywallText.featureLocked: '{feature} is available with Volary Premium.',
      PaywallText.benefitAdFree: 'Ad-free learning',
      PaywallText.benefitReader: 'Reader with PDF, DOCX and TXT',
      PaywallText.benefitAutoplay: 'Flashcard sets autoplay',
      PaywallText.trialFooter:
          'After trial, basic learning remains completely free.',
      PaywallText.buyLifetime: 'Buy lifetime for {price}',
      PaywallText.productUnavailable:
          'Premium is not available in this region',
      PaywallText.restore: 'Restore purchase',
      PaywallText.oneTimePayment: 'One-time payment. No subscription.',
      PaywallText.actionStartedPurchase:
          'Please confirm your purchase in Google Play.',
      PaywallText.actionStartedRestore:
          'Checking previous purchases in Google Play...',
      PaywallText.storeUnavailable:
          'Google Play is currently unavailable. Please try again later.',
      PaywallText.productNotConfigured:
          'Premium is not yet configured for this region.',
      PaywallText.actionFailed:
          'Could not complete the operation. Please try again.',
    },
    'uk': {
      PaywallText.title: 'Volary Premium',
      PaywallText.trialActive: 'Premium активний ще приблизно {hours} год.',
      PaywallText.featureLocked: '{feature} доступний з Volary Premium.',
      PaywallText.benefitAdFree: 'Навчання без реклами',
      PaywallText.benefitReader: 'Читалка з PDF, DOCX і TXT',
      PaywallText.benefitAutoplay: 'Автоплей наборів карток',
      PaywallText.trialFooter:
          'Після trial базове навчання залишиться безкоштовним.',
      PaywallText.buyLifetime: 'Придбати назавжди за {price}',
      PaywallText.productUnavailable: 'Premium недоступний у цьому регіоні',
      PaywallText.restore: 'Відновити покупку',
      PaywallText.oneTimePayment: 'Разова оплата. Без підписки.',
      PaywallText.actionStartedPurchase:
          'Підтвердьте покупку у Google Play.',
      PaywallText.actionStartedRestore:
          'Перевіряємо попередні покупки в Google Play.',
      PaywallText.storeUnavailable:
          'Google Play зараз недоступний. Спробуйте пізніше.',
      PaywallText.productNotConfigured:
          'Premium ще не налаштовано для цього регіону.',
      PaywallText.actionFailed:
          'Не вдалося виконати операцію. Спробуйте ще раз.',
    },
    'de': {
      PaywallText.title: 'Volary Premium',
      PaywallText.trialActive: 'Premium ist noch ca. {hours} Std. aktiv.',
      PaywallText.featureLocked: '{feature} ist mit Volary Premium verfügbar.',
      PaywallText.benefitAdFree: 'Lernen ohne Werbung',
      PaywallText.benefitReader: 'Reader mit PDF, DOCX und TXT',
      PaywallText.benefitAutoplay: 'Autoplay für Kartensets',
      PaywallText.trialFooter:
          'Nach der Testphase bleibt das Basislernen kostenlos.',
      PaywallText.buyLifetime: 'Dauerhaft kaufen für {price}',
      PaywallText.productUnavailable:
          'Premium ist in dieser Region nicht verfügbar',
      PaywallText.restore: 'Kauf wiederherstellen',
      PaywallText.oneTimePayment: 'Einmalige Zahlung. Kein Abo.',
      PaywallText.actionStartedPurchase:
          'Bitte bestätigen Sie den Kauf in Google Play.',
      PaywallText.actionStartedRestore:
          'Vorherige Käufe in Google Play werden überprüft...',
      PaywallText.storeUnavailable:
          'Google Play ist derzeit nicht verfügbar. Bitte versuchen Sie es später erneut.',
      PaywallText.productNotConfigured:
          'Premium ist für diese Region noch nicht eingerichtet.',
      PaywallText.actionFailed:
          'Vorgang konnte nicht abgeschlossen werden. Bitte erneut versuchen.',
    },
    'es': {
      PaywallText.title: 'Volary Premium',
      PaywallText.trialActive: 'Premium está activo durante unas {hours} h más.',
      PaywallText.featureLocked: '{feature} está disponible con Volary Premium.',
      PaywallText.benefitAdFree: 'Aprendizaje sin anuncios',
      PaywallText.benefitReader: 'Lector con PDF, DOCX y TXT',
      PaywallText.benefitAutoplay: 'Reproducción automática de tarjetas',
      PaywallText.trialFooter:
          'Tras la prueba, el aprendizaje básico seguirá siendo gratuito.',
      PaywallText.buyLifetime: 'Comprar para siempre por {price}',
      PaywallText.productUnavailable:
          'Premium no está disponible en esta región',
      PaywallText.restore: 'Restaurar compra',
      PaywallText.oneTimePayment: 'Pago único. Sin suscripción.',
      PaywallText.actionStartedPurchase:
          'Confirma la compra en Google Play.',
      PaywallText.actionStartedRestore:
          'Comprobando compras anteriores en Google Play...',
      PaywallText.storeUnavailable:
          'Google Play no está disponible en este momento. Inténtalo de nuevo más tarde.',
      PaywallText.productNotConfigured:
          'Premium aún no está configurado para esta región.',
      PaywallText.actionFailed:
          'No se pudo completar la operación. Inténtalo de nuevo.',
    },
  };

  String _langCode(BuildContext context) {
    final code = widget.languageCode?.toLowerCase().trim();
    if (code != null && _translations.containsKey(code)) {
      return code;
    }
    final locale = Localizations.maybeLocaleOf(context)?.languageCode.toLowerCase();
    if (locale != null && _translations.containsKey(locale)) {
      return locale;
    }
    return 'en';
  }

  String _string(PaywallText key, {Map<String, String>? params}) {
    final code = _langCode(context);
    var text = _translations[code]?[key] ?? _translations['en']![key]!;
    if (params != null) {
      params.forEach((paramKey, paramValue) {
        text = text.replaceAll('{$paramKey}', paramValue);
      });
    }
    return text;
  }

  @override
  void initState() {
    super.initState();
    _billing.addListener(_handleBillingChanged);
    _loadProduct();
  }

  @override
  void dispose() {
    _billing.removeListener(_handleBillingChanged);
    super.dispose();
  }

  void _handleBillingChanged() {
    if (!mounted) return;
    if (_billing.hasPremiumAccess) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
  }

  Future<void> _loadProduct() async {
    final product = await _billing.loadPremiumProduct();
    if (!mounted) return;
    setState(() {
      _product = product;
      _isLoading = false;
    });
  }

  Future<void> _buyPremium() async {
    setState(() => _isSubmitting = true);
    final result = await _billing.buyPremiumLifetime();
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    _showResult(result, isRestore: false);
  }

  Future<void> _restorePurchases() async {
    setState(() => _isSubmitting = true);
    final result = await _billing.restorePurchases();
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    _showResult(result, isRestore: true);
  }

  void _showResult(BillingActionResult result, {required bool isRestore}) {
    final key = switch (result) {
      BillingActionResult.started => isRestore
          ? PaywallText.actionStartedRestore
          : PaywallText.actionStartedPurchase,
      BillingActionResult.storeUnavailable => PaywallText.storeUnavailable,
      BillingActionResult.productUnavailable =>
        PaywallText.productNotConfigured,
      BillingActionResult.failed => PaywallText.actionFailed,
    };
    final message = _string(key);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTrial = _billing.isTrialActive;
    final trialHours = _billing.trialRemaining.inHours.clamp(1, 24);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.workspace_premium_rounded,
                    color: colorScheme.primary, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _string(PaywallText.title),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isTrial
                  ? _string(PaywallText.trialActive,
                      params: {'hours': trialHours.toString()})
                  : _string(PaywallText.featureLocked,
                      params: {'feature': widget.featureName}),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            _PremiumBenefit(
              icon: Icons.block_rounded,
              text: _string(PaywallText.benefitAdFree),
            ),
            _PremiumBenefit(
              icon: Icons.menu_book_rounded,
              text: _string(PaywallText.benefitReader),
            ),
            _PremiumBenefit(
              icon: Icons.play_circle_outline_rounded,
              text: _string(PaywallText.benefitAutoplay),
            ),
            const SizedBox(height: 20),
            if (isTrial)
              Text(
                _string(PaywallText.trialFooter),
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else if (_isLoading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ))
            else
              FilledButton.icon(
                onPressed:
                    _product == null || _isSubmitting ? null : _buyPremium,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.workspace_premium_rounded),
                label: Text(
                  _product == null
                      ? _string(PaywallText.productUnavailable)
                      : _string(PaywallText.buyLifetime,
                          params: {'price': _product!.price}),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            if (!isTrial) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isSubmitting ? null : _restorePurchases,
                  child: Text(_string(PaywallText.restore)),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Center(
              child: Text(
                _string(PaywallText.oneTimePayment),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumBenefit extends StatelessWidget {
  const _PremiumBenefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
