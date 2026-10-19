import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/billing_service.dart';

class PremiumPaywallSheet extends StatefulWidget {
  const PremiumPaywallSheet({super.key, required this.featureName});

  final String featureName;

  @override
  State<PremiumPaywallSheet> createState() => _PremiumPaywallSheetState();
}

class _PremiumPaywallSheetState extends State<PremiumPaywallSheet> {
  final BillingService _billing = BillingService();
  ProductDetails? _product;
  bool _isLoading = true;
  bool _isSubmitting = false;

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
    final message = switch (result) {
      BillingActionResult.started => isRestore
          ? 'Перевіряємо попередні покупки в Google Play.'
          : 'Підтвердьте покупку у Google Play.',
      BillingActionResult.storeUnavailable =>
        'Google Play зараз недоступний. Спробуйте пізніше.',
      BillingActionResult.productUnavailable =>
        'Premium ще не налаштовано для цього регіону.',
      BillingActionResult.failed =>
        'Не вдалося виконати операцію. Спробуйте ще раз.',
    };
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
                    'Volary Premium',
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
                  ? 'Premium активний ще приблизно $trialHours год.'
                  : '${widget.featureName} доступний з Volary Premium.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            const _PremiumBenefit(
              icon: Icons.block_rounded,
              text: 'Навчання без реклами',
            ),
            const _PremiumBenefit(
              icon: Icons.menu_book_rounded,
              text: 'Читалка з PDF, DOCX і TXT',
            ),
            const _PremiumBenefit(
              icon: Icons.play_circle_outline_rounded,
              text: 'Автоплей наборів карток',
            ),
            const SizedBox(height: 20),
            if (isTrial)
              Text(
                'Після trial базове навчання залишиться безкоштовним.',
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
                      ? 'Premium недоступний у цьому регіоні'
                      : 'Придбати назавжди за ${_product!.price}',
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
                  child: const Text('Відновити покупку'),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Разова оплата. Без підписки.',
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
