import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models.dart';
import '../../core/env_config.dart';
import '../../shared/widgets.dart';
import '../auth/auth_cubit.dart';
import 'shop_cubit.dart';

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});
  @override
  Widget build(BuildContext c) => BlocProvider(
    create: (d) => ShopCubit(
      repository(d),
      d.read<SharedPreferences>(),
      d.read<AuthCubit>().state.user?['country']?.toString() ?? '',
    )..load(),
    child: const ShopBody(),
  );
}

class ShopBody extends StatefulWidget {
  const ShopBody({super.key});
  @override
  State<ShopBody> createState() => _ShopBodyState();
}

class _ShopBodyState extends State<ShopBody> with WidgetsBindingObserver {
  final _searchFocus = FocusNode();
  final _searchController = TextEditingController();
  String category = 'all';
  String q = '';
  String qLabel = '';
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocus.addListener(() {
      if (mounted) setState(() => _searchFocused = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ShopCubit>().load();
    }
  }

  @override
  Widget build(BuildContext c) => BlocConsumer<ShopCubit, ShopState>(
    listener: (d, s) {
      if (s.error != null && s.products.isNotEmpty) notice(d, s.error!);
    },
    builder: (d, s) {
      final shop = d.read<ShopCubit>();
      final categories = {'all', ...s.products.map((p) => p.text('category'))};
      final products = s.products.where((p) {
        final inCategory = category == 'all' || p.text('category') == category;
        final matches = q.isEmpty || p.text('name').toLowerCase().contains(q);
        return inCategory && matches;
      }).toList();

      return RefreshIndicator(
        onRefresh: () => shop.load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _SearchCurrencyBar(
              focusNode: _searchFocus,
              controller: _searchController,
              searchFocused: _searchFocused,
              currency: s.currency.toUpperCase(),
              basketCount: s.items.fold(
                0,
                (sum, i) => sum + i.number('quantity'),
              ),
              busy: s.loading,
              onSearchChanged: (v) => setState(() {
                qLabel = v.trim();
                q = qLabel.toLowerCase();
              }),
              onCurrencyTap: () => _showRegionPicker(c, shop),
              onBasketTap: () => showModalBottomSheet<void>(
                context: c,
                isScrollControlled: true,
                builder: (sheet) => BlocProvider.value(
                  value: shop,
                  child: SizedBox(
                    height: MediaQuery.sizeOf(c).height * .85,
                    child: const BasketSheet(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final value in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(value),
                        selected: category == value,
                        onSelected: (_) => setState(() => category = value),
                      ),
                    ),
                ],
              ),
            ),
            if (s.loading)
              const Center(child: CircularProgressIndicator())
            else if (s.error != null && s.products.isEmpty)
              ErrorPanel(s.error!, retry: () => shop.load())
            else if (products.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BrandEmptyState(
                  asset: s.products.isEmpty
                      ? 'empty-catalogue'
                      : 'no-search-results',
                  title: s.products.isEmpty
                      ? 'The gear rail is bare.'
                      : 'Nothing matches that.',
                  message: s.products.isEmpty
                      ? 'New drops land here as soon as staff publish them. Check back soon.'
                      : category != 'all'
                      ? 'Nothing in "$category" matches "$qLabel". Try another search or category.'
                      : 'No product matches "$qLabel". Try a different word.',
                  action: s.products.isEmpty
                      ? null
                      : OutlinedButton.icon(
                          onPressed: () => setState(() {
                            q = '';
                            qLabel = '';
                            category = 'all';
                            _searchController.clear();
                          }),
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 18,
                          ),
                          label: const Text('Clear filters'),
                        ),
                ),
              )
            else
              for (final product in products)
                _ProductCard(
                  product: product,
                  currency: s.currency,
                  shop: shop,
                ),
          ],
        ),
      );
    },
  );

  Future<void> _showRegionPicker(BuildContext c, ShopCubit shop) async {
    const options = [
      (code: 'np', label: 'Nepal · NPR / Khalti'),
      (code: 'gb', label: 'Other countries · GBP / Stripe'),
    ];
    await showModalBottomSheet<void>(
      context: c,
      builder: (sheet) => BlocProvider.value(
        value: shop,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Shopping region'),
                subtitle: Text('Prices and payment method follow your region'),
              ),
              for (final option in options)
                ListTile(
                  title: Text(option.label),
                  trailing:
                      shop.state.currency == currencyForCountry(option.code)
                      ? Icon(
                          Icons.check,
                          color: Theme.of(sheet).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheet);
                    shop.load(country: option.code);
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchCurrencyBar extends StatelessWidget {
  const _SearchCurrencyBar({
    required this.focusNode,
    required this.controller,
    required this.searchFocused,
    required this.currency,
    required this.basketCount,
    required this.busy,
    required this.onSearchChanged,
    required this.onCurrencyTap,
    required this.onBasketTap,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final bool searchFocused;
  final String currency;
  final int basketCount;
  final bool busy;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCurrencyTap;
  final VoidCallback onBasketTap;

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onSearchChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Find products',
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );

    return Row(
      children: [
        // Region chip shares the row until the user starts searching, so the
        // field can take the full width once it matters.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: searchFocused
              ? const SizedBox(height: 48)
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CurrencyChip(
                    currency: currency,
                    onTap: busy ? null : onCurrencyTap,
                  ),
                ),
        ),
        Expanded(child: field),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Open basket',
          onPressed: busy ? null : onBasketTap,
          icon: Badge(
            label: Text('$basketCount'),
            isLabelVisible: basketCount > 0,
            child: const Icon(Icons.shopping_bag_outlined),
          ),
        ),
      ],
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({required this.currency, this.onTap});

  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    return Semantics(
      button: true,
      label: 'Shopping region, $currency. Tap to change.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currency,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.currency,
    required this.shop,
  });

  final Entity product;
  final String currency;
  final ShopCubit shop;

  @override
  Widget build(BuildContext c) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showModalBottomSheet<void>(
        context: c,
        isScrollControlled: true,
        builder: (sheet) => BlocProvider.value(
          value: shop,
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .8,
            child: ProductSheet(product),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrandImage(
              product.text('image'),
              width: double.infinity,
              height: 230,
            ),
            const SizedBox(height: 12),
            Text(product.text('name'), style: Theme.of(c).textTheme.titleLarge),
            Text(money(product.number('unitAmount'), currency)),
            Text(product.text('category')),
          ],
        ),
      ),
    ),
  );
}

class ProductSheet extends StatefulWidget {
  const ProductSheet(this.product, {super.key});
  final Entity product;
  @override
  State<ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<ProductSheet> {
  String? size;
  @override
  void initState() {
    super.initState();
    final options = widget.product.strings('sizes');
    if (options.length == 1) size = options.first;
  }

  @override
  Widget build(BuildContext c) => BlocBuilder<ShopCubit, ShopState>(
    builder: (d, s) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          BrandImage(
            widget.product.text('image'),
            width: double.infinity,
            height: 230,
          ),
          const SizedBox(height: 16),
          PageHeading(
            widget.product.text('name'),
            money(widget.product.number('unitAmount'), s.currency),
          ),
          Text(widget.product.text('description')),
          const SizedBox(height: 16),
          Text('Choose an option', style: Theme.of(c).textTheme.titleMedium),
          Wrap(
            spacing: 8,
            children: [
              for (final option in widget.product.strings('sizes'))
                ChoiceChip(
                  label: Text(option),
                  selected: option == size,
                  onSelected: s.saving
                      ? null
                      : (_) => setState(() => size = option),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: size == null || s.saving
                ? null
                : () async {
                    try {
                      await d.read<ShopCubit>().add(widget.product, size!);
                      if (d.mounted &&
                          d.read<ShopCubit>().state.error == null) {
                        notice(d, 'Added to basket.');
                        Navigator.pop(d);
                      }
                    } catch (error) {
                      if (d.mounted) notice(d, error.toString());
                    }
                  },
            icon: const Icon(Icons.shopping_bag_outlined),
            label: Text(s.saving ? 'Adding…' : 'Add to basket'),
          ),
        ],
      ),
    ),
  );
}

class BasketSheet extends StatelessWidget {
  const BasketSheet({super.key});
  @override
  Widget build(BuildContext c) => BlocBuilder<ShopCubit, ShopState>(
    builder: (d, s) {
      final shop = d.read<ShopCubit>();
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const PageHeading('Your basket', ''),
            if (s.error != null)
              Text(
                s.error!,
                style: TextStyle(color: Theme.of(c).colorScheme.error),
              ),
            if (s.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: BrandEmptyState(
                  asset: 'empty-basket',
                  title: 'No loot in the bag yet.',
                  message:
                      'Add a few pieces of pack gear and they will show up here.',
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(c),
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('Browse Pack Gear'),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(c);
                          c.push('/orders');
                        },
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('View your orders'),
                      ),
                    ],
                  ),
                ),
              ),
            for (final item in s.items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: BrandImage(
                          item.text('image'),
                          height: 60,
                          width: 60,
                        ),
                        title: Text(item.text('name')),
                        subtitle: Text(
                          '${item.text('size')}\n${money(item.number('unitAmount'), s.currency)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove ${item.text('name')}',
                          onPressed: s.saving
                              ? null
                              : () => shop.quantity(item, 0),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                      if (item.flag('unavailable'))
                        const Text(
                          'Unavailable. Remove this item before checkout.',
                        ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Decrease quantity',
                            onPressed: s.saving || item.number('quantity') <= 1
                                ? null
                                : () => shop.quantity(
                                    item,
                                    item.number('quantity') - 1,
                                  ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('${item.number('quantity')}'),
                          IconButton(
                            tooltip: 'Increase quantity',
                            onPressed:
                                s.saving ||
                                    item.number('quantity') >= 20 ||
                                    item.flag('unavailable')
                                ? null
                                : () => shop.quantity(
                                    item,
                                    item.number('quantity') + 1,
                                  ),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          const Spacer(),
                          Text(
                            money(
                              item.number('unitAmount') *
                                  item.number('quantity'),
                              s.currency,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (s.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Subtotal · ${money(s.subtotal, s.currency)}',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: s.saving || s.items.any((i) => i.flag('unavailable'))
                    ? null
                    : () => showModalBottomSheet<void>(
                        context: c,
                        isScrollControlled: true,
                        builder: (checkout) => BlocProvider.value(
                          value: shop,
                          child: SizedBox(
                            height: MediaQuery.sizeOf(c).height * .9,
                            child: const CheckoutSheet(),
                          ),
                        ),
                      ),
                child: Text(s.saving ? 'Saving basket…' : 'Pay on website'),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    c.push('/orders');
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('View your orders'),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class CheckoutSheet extends StatelessWidget {
  const CheckoutSheet({super.key});
  @override
  Widget build(BuildContext c) {
    final s = c.read<ShopCubit>().state;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const PageHeading(
              'Pay on the website',
              'Your basket is saved. Complete payment in your browser.',
            ),
            Text('Subtotal · ${money(s.subtotal, s.currency)}'),
            const SizedBox(height: 16),
            const Text(
              'Sign in with the same TWON account if asked. Review delivery, tax and the final total on the website. No payment details are collected in this app.',
            ),
            const SizedBox(height: 24),
            ActionButton(
              label: 'Continue on website',
              icon: Icons.open_in_new,
              action: () => openUrl(AppConfig.paymentUrl(currency: s.currency)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Back to basket'),
            ),
          ],
        ),
      ),
    );
  }
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with WidgetsBindingObserver {
  int revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) setState(() => revision++);
  }

  @override
  Widget build(BuildContext c) => CollectionView(
    key: ValueKey(revision),
    path: 'merch/orders',
    header: const PageHeading('My orders', ''),
    empty: 'Your orders will appear here.',
    builder: (d, order, r) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order #${order.id.substring(order.id.length > 8 ? order.id.length - 8 : 0)}',
              style: Theme.of(c).textTheme.titleMedium,
            ),
            Text(
              '${dateLabel(order.text('createdAt'))} · ${order.text('status')}',
            ),
            Text(
              money(
                order.number('amountTotal') > 0
                    ? order.number('amountTotal')
                    : order.number('subtotal'),
                order.text('currency', 'gbp'),
              ),
            ),
            for (final line in order.rows('items'))
              Text('${line['quantity']} × ${line['name']} · ${line['size']}'),
            const SizedBox(height: 12),
            Text('Delivery: ${order.text('fulfillmentStatus', 'unfulfilled')}'),
            if (order.text('trackingNumber').isNotEmpty)
              Text(
                '${order.text('carrier')} · ${order.text('trackingNumber')}',
              ),
            if (order.text('trackingUrl').isNotEmpty)
              TextButton(
                onPressed: () => openUrl(order.text('trackingUrl')),
                child: const Text('Track delivery'),
              ),
            if (order.text('status') == 'pending')
              Wrap(
                spacing: 8,
                children: [
                  ActionButton(
                    label: 'Check payment',
                    action: () async {
                      final result = asJson(
                        await repository(c).request(
                          'merch/orders/${order.id}/reconcile',
                          method: 'POST',
                        ),
                      );
                      if (result['status'] == 'paid' && c.mounted) {
                        await repository(c).request(
                          'merch/orders/${order.id}/acknowledge',
                          method: 'POST',
                        );
                      }
                      return result;
                    },
                    onSuccess: (_) => r(),
                  ),
                  ActionButton(
                    label: 'Resume payment',
                    tonal: true,
                    action: () => openUrl(
                      AppConfig.paymentUrl(
                        currency: order.text('currency', 'gbp'),
                        orderId: order.id,
                      ),
                    ),
                  ),
                ],
              ),
            if (order.text('status') == 'paid')
              ActionButton(
                label: 'Update basket after payment',
                tonal: true,
                action: () => repository(c).request(
                  'merch/orders/${order.id}/acknowledge',
                  method: 'POST',
                ),
                onSuccess: (_) => notice(c, 'Basket updated.'),
              ),
          ],
        ),
      ),
    ),
  );
}
