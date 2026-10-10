typedef Json = Map<String, dynamic>;
Json asJson(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> asRows(Object? value) =>
    value is List ? value.whereType<Map>().map(asJson).toList() : [];
String entityId(Object? value) => value is String
    ? value
    : '${asJson(value)['_id'] ?? asJson(value)['id'] ?? ''}';

class Entity {
  Entity(Json json) : data = Map.unmodifiable(json);
  final Json data;
  String get id => entityId(data);
  String text(String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  bool flag(String key) => data[key] == true;
  int number(String key) => (data[key] as num?)?.toInt() ?? 0;
  Json object(String key) => asJson(data[key]);
  List<Json> rows(String key) => asRows(data[key]);
  List<String> strings(String key) =>
      (data[key] as List? ?? []).map((v) => v.toString()).toList();
}

class ApiPage {
  const ApiPage(this.items, this.cursor);
  final List<Entity> items;
  final String? cursor;
  factory ApiPage.fromEnvelope(Json envelope) => ApiPage(
    asRows(envelope['data']).map(Entity.new).toList(),
    asJson(envelope['meta'])['nextCursor'] as String?,
  );
}

class AppFailure implements Exception {
  const AppFailure(this.message, {this.code = '', this.status});
  final String message, code;
  final int? status;
  @override
  String toString() => message;
}

String currencyForCountry(String country) =>
    ['np', 'nepal'].contains(country.trim().toLowerCase()) ? 'npr' : 'gbp';
