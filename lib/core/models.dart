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
  const AppFailure(this.message, {this.code = '', this.status, this.retryAfter});
  final String message, code;
  final int? status;

  /// From a `Retry-After` header (e.g. on 429), when the server sent one.
  final Duration? retryAfter;
  @override
  String toString() => message;
}

/// G2/G3/G4/G7 handoffs: clear copy for the backend's new error codes. Unknown
/// codes keep the server's message. `retryAfter` (429) gives the date to try again.
String errorCopy(
  String code,
  String fallback, {
  Duration? retryAfter,
  DateTime? now,
}) {
  switch (code) {
    case 'CLAN_DEMOTION_REASON_REQUIRED':
      return 'Give a reason when lowering a title. The member will see it.';
    case 'CLAN_TITLE_STALE':
      return 'This member\'s title changed meanwhile. Reload and try again.';
    case 'CLAN_TITLE_UNCHANGED':
      return 'The member already has this title.';
    case 'CLAN_DENIAL_REASON_REQUIRED':
      return 'Give a reason (5–500 characters). The member will see it.';
    case 'CLAN_PRIVILEGED_LEADER_ONLY':
      return 'Only the clan leader can decide this title.';
    case 'CLAN_SELF_PROMOTION':
      return 'Nobody decides their own request.';
    case 'CLAN_COOLING_OFF':
      return 'This title can be approved 48 hours after the request.';
    case 'CLAN_REQUEST_COOLDOWN':
      final at = retryAfter == null
          ? null
          : (now ?? DateTime.now()).add(retryAfter);
      return at == null
          ? 'You can ask again 7 days after a denial.'
          : 'You can ask again on ${at.toLocal().toIso8601String().split('T').first}.';
    case 'POINTS_UNAVAILABLE':
      return 'Pack Points are temporarily unavailable. Please try again later.';
    case 'EVENT_TIME_ZONE_INVALID':
      return 'Choose a valid time zone.';
    case 'EVENT_TIME_ZONE_REQUIRED':
      return 'Choose the time zone.';
    case 'EVENT_TIME_NONEXISTENT':
      return 'That time doesn\'t exist on that date in this time zone (a daylight-saving change). Choose another.';
    case 'EVENT_TIME_RANGE':
      return 'End time must be after the start.';
    case 'EVENT_START_IN_PAST':
      return 'Choose a future date and time.';
    case 'EVENT_RSVP_CLOSED':
      return 'RSVPs closed when the gathering started.';
    case 'EVENT_FULL':
      return 'This gathering is full.';
    case 'EVENT_CANCELLED':
      return 'This gathering was cancelled.';
    case 'EVENT_STARTED':
      return 'The time can\'t change after the gathering started.';
    case 'EVENT_CHANGED':
      return 'Someone else changed this gathering. Reload.';
    case 'EVENT_CAPACITY_BELOW_RSVPS':
      return 'More people are already registered than that capacity.';
    case 'EVENT_ENDED':
      return 'Past gatherings are kept for the record.';
  }
  return fallback;
}

String currencyForCountry(String country) =>
    ['np', 'nepal'].contains(country.trim().toLowerCase()) ? 'npr' : 'gbp';
