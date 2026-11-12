/// SEC-012: spreadsheet-safe CSV for exports (RFC 4180 quoting plus formula
/// neutralisation). Every cell is quoted and embedded quotes are doubled, so
/// commas, quotes and line breaks stay inside their cell. A cell that a
/// spreadsheet could evaluate as a formula is prefixed with an apostrophe.
library;

/// Formula or DDE starters (including full-width forms), tab, CR and LF.
final _formulaStart = RegExp('^[=+\\-@\t\r\n＝＋－＠]');

/// Leading whitespace and control characters some apps skip before parsing.
final _leadingIgnorable = RegExp(
  '^[\\s\u0000-\u001F\u007F ​-‍⁠﻿]+',
);

String csvCell(Object? value) {
  final text = value?.toString() ?? '';
  final visible = text.replaceFirst(_leadingIgnorable, '');
  final neutral = _formulaStart.hasMatch(text) || _formulaStart.hasMatch(visible)
      ? "'$text"
      : text;
  return '"${neutral.replaceAll('"', '""')}"';
}

/// Rows to CSV text with CRLF line breaks.
String toCsv(List<List<Object?>> rows) =>
    rows.map((row) => row.map(csvCell).join(',')).join('\r\n');

/// The organiser's attendee export: name and handle only (never contact data).
String attendeeCsv(List<Map<String, dynamic>> attendees) => toCsv([
  ['Name', 'Handle'],
  for (final row in attendees) [row['fullName'], row['handle']],
]);
