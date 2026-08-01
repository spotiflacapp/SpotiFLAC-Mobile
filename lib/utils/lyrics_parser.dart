import 'package:xml/xml.dart';

class LyricWord {
  final Duration time;
  final String text;

  const LyricWord({required this.time, required this.text});
}

class LyricLine {
  final Duration time;
  final Duration? end;
  final String text;
  final List<LyricWord> words;

  const LyricLine({
    required this.time,
    this.end,
    required this.text,
    this.words = const [],
  });

  bool get hasWordTiming => words.isNotEmpty;
}

class ParsedLyrics {
  final bool synced;
  final bool wordSynced;
  final List<LyricLine> lines;
  final String plainText;

  const ParsedLyrics({
    required this.synced,
    required this.wordSynced,
    required this.lines,
    required this.plainText,
  });

  bool get isEmpty => lines.isEmpty && plainText.trim().isEmpty;

  static const ParsedLyrics empty = ParsedLyrics(
    synced: false,
    wordSynced: false,
    lines: [],
    plainText: '',
  );
}

class LyricsParser {
  LyricsParser._();

  // [mm:ss.xx] or [mm:ss.xxx] or [mm:ss]
  static final RegExp _lineTimeTag = RegExp(
    r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
  );

  // <mm:ss.xx> inline word timestamp (enhanced LRC).
  static final RegExp _wordTimeTag = RegExp(
    r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>',
  );

  // ID tags such as [ti:..], [ar:..], [offset:..].
  static final RegExp _idTag = RegExp(
    r'^\[(ti|ar|al|by|offset|length|re|ve|tool|au|la|encoder):.*\]$',
    caseSensitive: false,
  );

  static ParsedLyrics parse(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return ParsedLyrics.empty;

    if (_looksLikeTtml(text)) {
      final ttml = _parseTtml(text);
      if (ttml != null && ttml.lines.isNotEmpty) return ttml;
    }

    return _parseLrcOrPlain(text);
  }

  static bool _looksLikeTtml(String text) {
    final head = text.trimLeft();
    return head.startsWith('<?xml') ||
        head.startsWith('<tt') ||
        head.contains('<tt ') ||
        head.contains('http://www.w3.org/ns/ttml');
  }

  static Duration? _toDuration(String? min, String? sec, String? frac) {
    if (min == null || sec == null) return null;
    final m = int.tryParse(min) ?? 0;
    final s = int.tryParse(sec) ?? 0;
    var ms = 0;
    if (frac != null && frac.isNotEmpty) {
      // Normalize to milliseconds regardless of 2 or 3 digit fractions.
      final padded = frac.padRight(3, '0').substring(0, 3);
      ms = int.tryParse(padded) ?? 0;
    }
    return Duration(minutes: m, seconds: s, milliseconds: ms);
  }

  static ParsedLyrics _parseLrcOrPlain(String text) {
    final rawLines = text.split(RegExp(r'\r\n|\r|\n'));
    final parsed = <LyricLine>[];
    final plainBuffer = <String>[];
    var sawTimestamp = false;
    var sawWordTiming = false;
    var offsetMs = 0;

    for (final rawLine in rawLines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;

      // Capture [offset:] for timing correction, drop other ID tags.
      final idMatch = _idTag.firstMatch(line.trim());
      if (idMatch != null) {
        final key = idMatch.group(1)!.toLowerCase();
        if (key == 'offset') {
          final value = line
              .substring(line.indexOf(':') + 1)
              .replaceAll(']', '')
              .trim();
          offsetMs = int.tryParse(value) ?? 0;
        }
        continue;
      }

      final timeMatches = _lineTimeTag.allMatches(line).toList();
      if (timeMatches.isEmpty) {
        // No timestamp: treat as plain text line.
        plainBuffer.add(line.trim());
        continue;
      }

      sawTimestamp = true;

      // Strip leading line timestamps to obtain the lyric content.
      final lastTag = timeMatches.last;
      final content = line.substring(lastTag.end).trim();

      // Enhanced LRC word timestamps inside the content.
      final words = _parseWords(content);
      if (words.isNotEmpty) sawWordTiming = true;
      final cleanContent = content.replaceAll(_wordTimeTag, '').trim();
      plainBuffer.add(cleanContent);

      // A line can have multiple timestamps (repeated chorus).
      for (final tm in timeMatches) {
        final d = _toDuration(tm.group(1), tm.group(2), tm.group(3));
        if (d == null) continue;
        parsed.add(LyricLine(time: d, text: cleanContent, words: words));
      }
    }

    if (!sawTimestamp) {
      // Pure plain text.
      return ParsedLyrics(
        synced: false,
        wordSynced: false,
        lines: const [],
        plainText: rawLines
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && _idTag.firstMatch(l) == null)
            .join('\n'),
      );
    }

    parsed.sort((a, b) => a.time.compareTo(b.time));

    final adjusted = offsetMs == 0
        ? parsed
        : parsed
              .map(
                (l) => LyricLine(
                  time: _shift(l.time, offsetMs),
                  end: l.end,
                  text: l.text,
                  words: l.words
                      .map(
                        (w) => LyricWord(
                          time: _shift(w.time, offsetMs),
                          text: w.text,
                        ),
                      )
                      .toList(),
                ),
              )
              .toList();

    return ParsedLyrics(
      synced: true,
      wordSynced: sawWordTiming,
      lines: adjusted,
      plainText: plainBuffer.where((l) => l.isNotEmpty).join('\n'),
    );
  }

  static Duration _shift(Duration d, int offsetMs) {
    // LRC offset: positive value shifts lyrics earlier.
    final ms = d.inMilliseconds - offsetMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  static List<LyricWord> _parseWords(String content) {
    final matches = _wordTimeTag.allMatches(content).toList();
    if (matches.isEmpty) return const [];

    final words = <LyricWord>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final d = _toDuration(m.group(1), m.group(2), m.group(3));
      if (d == null) continue;
      final start = m.end;
      final end = i + 1 < matches.length
          ? matches[i + 1].start
          : content.length;
      final word = content.substring(start, end);
      if (word.trim().isEmpty) continue;
      words.add(LyricWord(time: d, text: word));
    }
    return words;
  }

  static ParsedLyrics? _parseTtml(String text) {
    try {
      final doc = XmlDocument.parse(text);
      final paragraphs = doc.findAllElements('p').toList();
      if (paragraphs.isEmpty) return null;

      final lines = <LyricLine>[];
      final plain = <String>[];
      var sawWords = false;

      for (final p in paragraphs) {
        final begin = _parseClock(p.getAttribute('begin'));
        final end = _parseClock(p.getAttribute('end'));

        // Word/syllable spans carry their own begin attribute.
        final spans = p.findElements('span').toList();
        final words = <LyricWord>[];
        if (spans.isNotEmpty) {
          for (final span in spans) {
            final sBegin = _parseClock(span.getAttribute('begin'));
            final spanText = span.innerText;
            if (sBegin != null && spanText.trim().isNotEmpty) {
              words.add(LyricWord(time: sBegin, text: '$spanText '));
            }
          }
        }
        if (words.isNotEmpty) sawWords = true;

        final lineText = p.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (lineText.isEmpty && words.isEmpty) continue;
        plain.add(lineText);

        if (begin != null) {
          lines.add(
            LyricLine(time: begin, end: end, text: lineText, words: words),
          );
        }
      }

      if (lines.isEmpty) {
        return ParsedLyrics(
          synced: false,
          wordSynced: false,
          lines: const [],
          plainText: plain.join('\n'),
        );
      }

      lines.sort((a, b) => a.time.compareTo(b.time));
      return ParsedLyrics(
        synced: true,
        wordSynced: sawWords,
        lines: lines,
        plainText: plain.where((l) => l.isNotEmpty).join('\n'),
      );
    } catch (_) {
      return null;
    }
  }

  // TTML clock value: "mm:ss.fff", "hh:mm:ss.fff" or "12.5s".
  static Duration? _parseClock(String? value) {
    if (value == null || value.isEmpty) return null;
    final v = value.trim();

    if (v.endsWith('s') && !v.contains(':')) {
      final seconds = double.tryParse(v.substring(0, v.length - 1));
      if (seconds == null) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    }

    final parts = v.split(':');
    try {
      if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final s = double.parse(parts[2]);
        return Duration(hours: h, minutes: m, milliseconds: (s * 1000).round());
      } else if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final s = double.parse(parts[1]);
        return Duration(minutes: m, milliseconds: (s * 1000).round());
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static int activeIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }
}
