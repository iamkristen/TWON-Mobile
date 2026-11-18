import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/core/api.dart';
import 'package:twon_mobile/core/models.dart';
import 'package:twon_mobile/features/account/account_pages.dart';
import 'package:twon_mobile/features/clans/clan_pages.dart';
import 'package:twon_mobile/features/gatherings/gathering_pages.dart';

/// G12 handoffs A, B, C and F: Mobile handles the G2/G3/G4/G7 backend
/// behaviour that applies even with every reward feature off.
class RecordingApi implements AppRepository {
  final calls = <({String method, String path, Object? body})>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    Json? query,
    bool authenticated = true,
    CancelToken? cancel,
  }) async {
    calls.add((method: method, path: path, body: body));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('A (G2): changing a member title', () {
    test(
      'lowering a title needs a reason; nothing is sent without one',
      () async {
        final api = RecordingApi();
        await expectLater(
          saveMemberChange(
            api,
            clanId: 'c',
            memberId: 'm',
            currentRole: 'member',
            currentTitle: 'Den Master',
            values: {'role': 'member', 'title': 'Pup', 'reason': ' '},
          ),
          throwsA(
            isA<AppFailure>().having(
              (f) => f.code,
              'code',
              'CLAN_DEMOTION_REASON_REQUIRED',
            ),
          ),
        );
        expect(api.calls, isEmpty);
      },
    );
    test(
      'sends only what changed, with the reason and the title the leader saw',
      () async {
        final api = RecordingApi();
        await saveMemberChange(
          api,
          clanId: 'c',
          memberId: 'm',
          currentRole: 'member',
          currentTitle: 'Den Master',
          values: {
            'role': 'member',
            'title': 'Pup',
            'reason': 'Inactive for months',
          },
        );
        expect(api.calls.single.path, 'clans/c/members/m/title');
        expect(api.calls.single.body, {
          'title': 'Pup',
          'expectedTitle': 'Den Master',
          'reason': 'Inactive for months',
        });
      },
    );
    test(
      'raising a title needs no reason; a role-only change sends only the role',
      () async {
        final api = RecordingApi();
        await saveMemberChange(
          api,
          clanId: 'c',
          memberId: 'm',
          currentRole: 'member',
          currentTitle: 'Pup',
          values: {'role': 'member', 'title': 'Alpha', 'reason': ''},
        );
        expect(api.calls.single.body, {
          'title': 'Alpha',
          'expectedTitle': 'Pup',
        });
        final api2 = RecordingApi();
        await saveMemberChange(
          api2,
          clanId: 'c',
          memberId: 'm',
          currentRole: 'member',
          currentTitle: 'Pup',
          values: {'role': 'officer', 'title': 'Pup'},
        );
        expect(api2.calls.map((c) => c.path), ['clans/c/members/m/role']);
        expect(
          () => saveMemberChange(
            RecordingApi(),
            clanId: 'c',
            memberId: 'm',
            currentRole: 'member',
            currentTitle: 'Pup',
            values: {'role': 'member', 'title': 'Pup'},
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );
    test('409 stale and unchanged get clear copy', () {
      expect(errorCopy('CLAN_TITLE_STALE', 'x'), contains('Reload'));
      expect(errorCopy('CLAN_TITLE_UNCHANGED', 'x'), contains('already has'));
    });
  });

  group('B (G3): private points and the ranking setting', () {
    test("another member's private points show as Private, never 0", () {
      expect(statLabel('packPoints', null), 'Private');
      expect(statLabel('packPoints', 0), '0');
      expect(statLabel('packPoints', 120), '120');
      expect(statLabel('followerCount', null), '0');
    });
    test('points temporarily unavailable is explained (never 0)', () {
      expect(
        errorCopy('POINTS_UNAVAILABLE', 'x'),
        contains('temporarily unavailable'),
      );
    });
  });

  group('C (G4): gatherings', () {
    test(
      'shows the organiser wall clock in the gathering zone, and flags an assumed zone',
      () {
        expect(
          eventWhen({
            'date': '2027-01-10T00:00:00.000Z',
            'time': '10:00',
            'endTime': '12:30',
            'timeZone': 'Asia/Kathmandu',
          }),
          allOf(
            contains('10:00–12:30'),
            contains('(Asia/Kathmandu)'),
            isNot(contains('UTC')),
          ),
        );
        expect(
          eventWhen({
            'date': '2027-01-10',
            'time': '10:00',
            'timeZone': 'UTC',
            'timeZoneAssumed': true,
          }),
          contains('time zone not confirmed'),
        );
      },
    );
    test(
      'the RSVP control follows the server phase, rsvpOpen and spotsLeft',
      () {
        expect(
          rsvpState({
            'phase': 'upcoming',
            'rsvpOpen': true,
            'spotsLeft': 3,
          }, attending: false).label,
          'Join gathering',
        );
        expect(
          rsvpState({
            'phase': 'upcoming',
            'rsvpOpen': true,
            'spotsLeft': 0,
          }, attending: false),
          (label: 'Full', action: null),
        );
        expect(
          rsvpState({
            'phase': 'upcoming',
            'rsvpOpen': true,
          }, attending: true).action,
          'leave',
        );
        expect(
          rsvpState({'phase': 'live', 'rsvpOpen': false}, attending: false),
          (label: 'Started', action: null),
        );
        expect(
          rsvpState({
            'phase': 'ended',
            'rsvpOpen': false,
          }, attending: true).action,
          isNull,
        );
        expect(
          rsvpState({
            'phase': 'cancelled',
            'rsvpOpen': false,
          }, attending: true).action,
          'leave',
        ); // withdraw from a cancelled one
        expect(
          rsvpState({
            'phase': 'cancelled',
            'rsvpOpen': false,
          }, attending: false),
          (label: 'Cancelled', action: null),
        );
      },
    );
    test(
      'the schedule is editable only before the start; the organiser picks an IANA zone',
      () {
        expect(scheduleEditable(null), isTrue);
        expect(scheduleEditable({'phase': 'upcoming'}), isTrue);
        expect(scheduleEditable({'phase': 'live'}), isFalse);
        expect(timeZoneOptions(null), contains('Asia/Kathmandu'));
        expect(
          timeZoneOptions({'timeZone': 'Pacific/Auckland'}).first,
          'Pacific/Auckland',
        );
      },
    );
    test('every new gathering error has clear copy', () {
      for (final code in [
        'EVENT_TIME_ZONE_INVALID',
        'EVENT_TIME_ZONE_REQUIRED',
        'EVENT_TIME_NONEXISTENT',
        'EVENT_TIME_RANGE',
        'EVENT_START_IN_PAST',
        'EVENT_RSVP_CLOSED',
        'EVENT_FULL',
        'EVENT_CANCELLED',
        'EVENT_STARTED',
        'EVENT_CHANGED',
        'EVENT_CAPACITY_BELOW_RSVPS',
        'EVENT_ENDED',
      ]) {
        expect(errorCopy(code, 'SERVER'), isNot('SERVER'), reason: code);
      }
    });
  });

  group('F (G7): title requests', () {
    test(
      'a denial needs a reason of 5–500 characters, sent as { reason }',
      () async {
        final api = RecordingApi();
        await expectLater(
          denyTitleRequest(api, clanId: 'c', requestId: 'r', reason: 'no'),
          throwsA(isA<AppFailure>()),
        );
        expect(api.calls, isEmpty);
        await denyTitleRequest(
          api,
          clanId: 'c',
          requestId: 'r',
          reason: '  Not active enough yet  ',
        );
        expect(
          [api.calls.single.method, api.calls.single.path],
          ['POST', 'clans/c/title-requests/r/deny'],
        );
        expect(api.calls.single.body, {'reason': 'Not active enough yet'});
      },
    );
    test(
      'the cooldown says when to ask again (from Retry-After); leader-only titles are explained',
      () {
        final now = DateTime.utc(2026, 11, 18, 12);
        expect(
          errorCopy(
            'CLAN_REQUEST_COOLDOWN',
            'x',
            retryAfter: const Duration(days: 7),
            now: now,
          ),
          contains('2026-11-25'),
        );
        expect(errorCopy('CLAN_REQUEST_COOLDOWN', 'x'), contains('7 days'));
        expect(
          errorCopy('CLAN_PRIVILEGED_LEADER_ONLY', 'x'),
          contains('leader'),
        );
        expect(errorCopy('UNKNOWN_CODE', 'Server says'), 'Server says');
      },
    );
  });
}
