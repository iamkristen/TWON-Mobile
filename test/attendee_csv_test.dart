import 'package:flutter_test/flutter_test.dart';
import 'package:twon_mobile/shared/csv.dart';

/// SEC-012 (Flutter): the shared attendee CSV has no contact data and cannot
/// carry spreadsheet formulas, while staying RFC 4180 compatible.
void main() {
  test('neutralises formula payloads, including after leading whitespace', () {
    const cases = {
      '=HYPERLINK("http://evil","x")': "\"'=HYPERLINK(\"\"http://evil\"\",\"\"x\"\")\"",
      '+SUM(1)': "\"'+SUM(1)\"",
      '-2+3': "\"'-2+3\"",
      '@cmd': "\"'@cmd\"",
      '\t=1': "\"'\t=1\"",
      '\r=1': "\"'\r=1\"",
      '   =1': "\"'   =1\"",
      '​=1': "\"'​=1\"",
      '＝1+1': "\"'＝1+1\"",
    };
    cases.forEach((input, expected) => expect(csvCell(input), expected, reason: input));
  });

  test('quotes commas, quotes, line breaks and Unicode without altering plain text', () {
    expect(csvCell('Ram, Shyam'), '"Ram, Shyam"');
    expect(csvCell('The "Wolf"'), '"The ""Wolf"""');
    expect(csvCell('line1\nline2'), '"line1\nline2"');
    expect(csvCell('राम श्रेष्ठ'), '"राम श्रेष्ठ"');
    expect(csvCell('a-b'), '"a-b"');
    expect(csvCell(null), '""');
  });

  test('attendee export has Name and Handle only, even if a server sent more', () {
    final csv = attendeeCsv([
      {'userId': 'u1', 'fullName': '=1+1', 'handle': 'wolf', 'email': 'leak@example.test'},
      {'userId': 'u2', 'fullName': 'Asha', 'handle': 'asha'},
    ]);
    expect(csv, '"Name","Handle"\r\n"\'=1+1","wolf"\r\n"Asha","asha"');
    expect(csv.toLowerCase(), isNot(contains('email')));
    expect(csv, isNot(contains('@example.test')));
  });
}
