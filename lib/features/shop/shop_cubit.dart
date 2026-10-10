import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api.dart';
import '../../core/models.dart';

class ShopState {
  const ShopState({
    this.currency = 'gbp',
    this.products = const [],
    this.items = const [],
    this.settings = const {},
    this.revision = 0,
    this.loading = false,
    this.saving = false,
    this.error,
  });
  final String currency;
  final List<Entity> products, items;
  final Json settings;
  final int revision;
  final bool loading, saving;
  final String? error;
  int get subtotal => items.fold(
    0,
    (sum, item) => sum + item.number('unitAmount') * item.number('quantity'),
  );
}

class ShopCubit extends Cubit<ShopState> {
  ShopCubit(this.api, this.preferences, String country)
    : super(
        ShopState(
          currency: currencyForCountry(
            preferences.getString('shop.country') ?? country,
          ),
        ),
      );
  final AppRepository api;
  final SharedPreferences preferences;
  int generation = 0;
  Future<void> load({String? country}) async {
    if (state.saving) return;
    final currency = country == null
        ? state.currency
        : currencyForCountry(country);
    if (country != null) await preferences.setString('shop.country', country);
    final version = ++generation;
    emit(ShopState(currency: currency, loading: true));
    try {
      final result = await Future.wait([
        api.request('merch/products', query: {'currency': currency}),
        api.request('merch/basket', query: {'currency': currency}),
        api.request('merch/shop-settings'),
      ]);
      if (isClosed || generation != version) return;
      final basket = asJson(result[1]);
      emit(
        ShopState(
          currency: currency,
          products: asRows(result[0]).map(Entity.new).toList(),
          items: asRows(basket['items']).map(Entity.new).toList(),
          revision: (basket['revision'] as num).toInt(),
          settings: asJson(result[2]),
        ),
      );
    } catch (error) {
      if (!isClosed && generation == version) {
        emit(ShopState(currency: currency, error: error.toString()));
      }
    }
  }

  Future<void> save(List<Json> items) async {
    if (state.saving || state.loading) return;
    final prior = state;
    emit(
      ShopState(
        currency: prior.currency,
        products: prior.products,
        items: prior.items,
        revision: prior.revision,
        settings: prior.settings,
        saving: true,
      ),
    );
    try {
      final result = asJson(
        await api.request(
          'merch/basket',
          method: 'PUT',
          body: {
            'currency': prior.currency,
            'revision': prior.revision,
            'items': items,
          },
        ),
      );
      if (!isClosed) {
        emit(
          ShopState(
            currency: prior.currency,
            products: prior.products,
            items: asRows(result['items']).map(Entity.new).toList(),
            revision: (result['revision'] as num).toInt(),
            settings: prior.settings,
          ),
        );
      }
    } catch (error) {
      if (isClosed) return;
      emit(
        ShopState(
          currency: prior.currency,
          products: prior.products,
          items: prior.items,
          revision: prior.revision,
          settings: prior.settings,
          error: error.toString(),
        ),
      );
      if (error is AppFailure && error.status == 409) {
        await load();
        if (!isClosed) {
          emit(
            ShopState(
              currency: state.currency,
              products: state.products,
              items: state.items,
              revision: state.revision,
              settings: state.settings,
              error:
                  'The basket changed on another device. Review the updated basket and try again.',
            ),
          );
        }
      }
    }
  }

  List<Json> get wire => state.items
      .map(
        (e) => {
          'productId': e.id,
          'size': e.text('size'),
          'quantity': e.number('quantity'),
        },
      )
      .toList();
  Future<void> add(Entity product, String size) {
    final items = wire;
    final index = items.indexWhere(
      (i) => i['productId'] == product.id && i['size'] == size,
    );
    if (index < 0) {
      items.add({'productId': product.id, 'size': size, 'quantity': 1});
    } else {
      if (items[index]['quantity'] >= 20) {
        return Future.error(const AppFailure('Maximum quantity is 20.'));
      }
      items[index]['quantity']++;
    }
    return save(items);
  }

  Future<void> quantity(Entity item, int value) {
    final items = wire
        .where(
          (i) => !(i['productId'] == item.id && i['size'] == item.text('size')),
        )
        .toList();
    if (value > 0) {
      items.add({
        'productId': item.id,
        'size': item.text('size'),
        'quantity': value.clamp(1, 20),
      });
    }
    return save(items);
  }
}
