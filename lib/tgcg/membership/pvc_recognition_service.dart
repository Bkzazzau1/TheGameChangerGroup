import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class PvcRecognitionResult {
  const PvcRecognitionResult({
    required this.imagePath,
    required this.imageName,
    required this.rawText,
    this.fullName,
    this.voterId,
    this.delim,
    this.dateOfBirth,
    this.gender,
    this.occupation,
  });

  final String imagePath;
  final String imageName;
  final String rawText;
  final String? fullName;
  final String? voterId;

  /// Polling unit code from the card's DELIM line, as 18-23-01-001.
  final String? delim;
  final DateTime? dateOfBirth;

  /// male or female.
  final String? gender;
  final String? occupation;

  bool get hasRecognizedText => rawText.trim().isNotEmpty;
}

/// Reads the front of a PVC with the phone's text recognition. What it reads
/// saves typing; it never shows that the card is genuine.
class PvcRecognitionService {
  PvcRecognitionService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Text recognition runs in the Android and iPhone apps only. Elsewhere the
  /// photo is kept and nothing is read from it.
  static bool get canReadText =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<PvcRecognitionResult?> captureAndRecognize() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 94,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (image == null) return null;
    return recognizeImage(image);
  }

  Future<PvcRecognitionResult?> pickAndRecognize() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    return recognizeImage(image);
  }

  Future<PvcRecognitionResult> recognizeImage(XFile image) async {
    if (!canReadText) {
      return PvcRecognitionResult(
        imagePath: image.path,
        imageName: image.name,
        rawText: '',
      );
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      return fromText(recognized.text, imagePath: image.path, imageName: image.name);
    } finally {
      await recognizer.close();
    }
  }

  /// The fields in the text read off a card: by the phone, or by the server
  /// for a photo added in a browser.
  static PvcRecognitionResult fromText(
    String text, {
    String imagePath = '',
    String imageName = '',
  }) =>
      PvcRecognitionResult(
        imagePath: imagePath,
        imageName: imageName,
        rawText: text.trim(),
        fullName: extractName(text),
        voterId: extractVoterId(text),
        delim: extractDelim(text),
        dateOfBirth: extractDateOfBirth(text),
        gender: extractGender(text),
        occupation: extractOccupation(text),
      );

  static final _delim = RegExp(
    r'(?<![\d/-])(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,3})(?![\d/-])',
  );

  static final _codeLabel = RegExp(r'\b(?:CODE|DELIM)\b', caseSensitive: false);

  /// Reads the polling unit code (state/LGA/ward/unit) and normalises it to
  /// 18-23-01-014. Cards print it as CODE: 18-23-01-014 (their DELIM line names
  /// the state, LGA and ward); older cards may label the code DELIM. A labelled
  /// code wins over any other match, and after the label nine digits whose
  /// dashes were lost in reading still count.
  static String? extractDelim(String text) {
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).toList();
    String? fromLine(String line) {
      final match = _delim.firstMatch(line);
      if (match == null) return null;
      final parts = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
      // INEC numbers states 1-37 (FCT is 37).
      if (parts[0] < 1 || parts[0] > 37 || parts.skip(1).any((p) => p < 1)) return null;
      String pad(int value, int width) => '$value'.padLeft(width, '0');
      return '${pad(parts[0], 2)}-${pad(parts[1], 2)}-${pad(parts[2], 2)}-${pad(parts[3], 3)}';
    }

    String? fromNineDigits(String value) {
      final digits = RegExp(r'(?<!\d)\d{9}(?!\d)').stringMatch(value);
      if (digits == null) return null;
      return fromLine('${digits.substring(0, 2)}-${digits.substring(2, 4)}-'
          '${digits.substring(4, 6)}-${digits.substring(6)}');
    }

    for (var i = 0; i < lines.length; i++) {
      final label = _codeLabel.firstMatch(lines[i]);
      if (label == null) continue;
      final after = _value(lines[i].substring(label.end));
      final code = fromLine(after) ??
          fromNineDigits(after) ??
          (i + 1 < lines.length ? fromLine(lines[i + 1]) : null);
      if (code != null) return code;
    }
    for (final line in lines) {
      final code = fromLine(line);
      if (code != null) return code;
    }
    return null;
  }

  // --- labelled fields -------------------------------------------------------------

  /// Words that label a field on the card, as whole words. A value stops where
  /// the next label starts, in case the reader ran two fields into one line.
  static final _anyLabel = RegExp(
    r'\b(?:VIN|CODE|DELIM|(?:FULL\s+|FIRST\s+|OTHER\s+|MIDDLE\s+|GIVEN\s+|LAST\s+)?NAMES?|SURNAME|'
    r'DATE\s+OF\s+BIRTH|D\.?O\.?B|GENDER|SEX|OCCUPATION|ADDRESS|POLLING\s+UNIT)\b',
    caseSensitive: false,
  );

  static List<String> _lines(String text) => text
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  /// Text after a label: without the separator (which readers sometimes see as
  /// a quote mark), and up to the next label.
  static String _value(String text) {
    final value = text.replaceFirst(RegExp(r'''^\s*[:;.,#"'\-–]*\s*'''), '');
    final next = _anyLabel.firstMatch(value);
    return (next == null ? value : value.substring(0, next.start)).trim();
  }

  /// The first value [read] accepts for [label]: from the rest of the label's
  /// line, or else the next line. Cards print some labels side by side (DATE OF
  /// BIRTH and GENDER), so a reader can put both labels on one line and both
  /// values on the next.
  static T? _labelled<T>(String text, RegExp label, T? Function(String value) read) {
    final lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
      final match = label.firstMatch(lines[i]);
      if (match == null) continue;
      final rest = _value(lines[i].substring(match.end));
      final next = i + 1 < lines.length && _anyLabel.matchAsPrefix(lines[i + 1]) == null
          ? _value(lines[i + 1])
          : '';
      final value = (rest.isEmpty ? null : read(rest)) ?? (next.isEmpty ? null : read(next));
      if (value != null) return value;
    }
    return null;
  }

  // --- name ------------------------------------------------------------------------

  static final _nameLabel = RegExp(
    r'(?<!\b(?:FIRST|OTHER|MIDDLE|GIVEN|LAST|UNIT)\s+)\b(?:FULL\s+)?NAMES?\b',
    caseSensitive: false,
  );
  static final _surnameLabel = RegExp(r'\b(?:SURNAME|LAST\s+NAME)\b', caseSensitive: false);
  static final _otherNamesLabel =
      RegExp(r'\b(?:OTHER|FIRST|GIVEN)\s+NAMES?\b', caseSensitive: false);
  static final _middleNameLabel = RegExp(r'\bMIDDLE\s+NAMES?\b', caseSensitive: false);

  /// The card's own way of printing the name, unlabelled: SURNAME, OTHER NAMES.
  static final _commaName =
      RegExp(r"\b([A-Z][A-Z'\-]+),\s*([A-Z][A-Z'\-]+(?:\s+[A-Z][A-Z'\-]+){0,4})");

  /// The holder's name: a NAME line, SURNAME with OTHER (or FIRST and MIDDLE)
  /// NAMES, or else the card's SURNAME, OTHER NAMES line. A surname alone is
  /// not a full name, and other unlabelled lines are never taken for one.
  static String? extractName(String text) {
    final full = _labelled(text, _nameLabel, (value) => _name(value, minWords: 2));
    if (full != null) return full;
    final surname = _labelled(text, _surnameLabel, _name);
    final others = _labelled(text, _otherNamesLabel, _name);
    if (surname != null && others != null) {
      final middle = _labelled(text, _middleNameLabel, _name);
      return [surname, others, ?middle].join(' ');
    }
    return _cardName(text);
  }

  /// SURNAME, OTHER NAMES as printed. Readers add stray marks around it, so
  /// only the capitalised words next to the comma count. The address (NO34
  /// ANGUWAN KAHU, ZARIA CITY) is printed last and never counts.
  static String? _cardName(String text) {
    for (final line in _lines(text)) {
      if (RegExp(r'\bADDRESS\b', caseSensitive: false).hasMatch(line)) return null;
      if (RegExp(r'[A-Za-z]\d|\d[A-Za-z]').hasMatch(line)) continue; // a house number
      if (_anyLabel.hasMatch(line)) continue;
      final match = _commaName.firstMatch(line);
      if (match != null) return _titleCase('${match[1]} ${match[2]}');
    }
    return null;
  }

  static String? _name(String value, {int minWords = 1}) {
    if (RegExp(r'\d').hasMatch(value)) return null;
    final cleaned = value
        .replaceAll(RegExp(r"[^A-Za-z .'-]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[ ,.\-]+|[ ,.\-]+$'), '');
    final words = cleaned.split(' ').where((word) => RegExp(r'[A-Za-z]{2,}').hasMatch(word));
    if (words.length < minWords || words.length > 6) return null;
    return _titleCase(cleaned);
  }

  // --- VIN -------------------------------------------------------------------------

  static final _vinLabel = RegExp(
    r"\b(?:VIN|VOTER'?S?\s+(?:ID(?:ENTIFICATION)?\s*)?(?:NO|NUMBER)|VOTER\s+ID)\b",
    caseSensitive: false,
  );

  /// A VIN printed in groups, for when its label was misread ("VlN").
  static final _groupedVin = RegExp(
    r'(?<![A-Z0-9])([A-Z0-9]{4})[ -]?([A-Z0-9]{4})[ -]?([A-Z0-9]{4})[ -]?([A-Z0-9]{4})[ -]?([A-Z0-9]{3})(?![A-Z0-9])',
    caseSensitive: false,
  );

  /// Reads the VIN: exactly 19 letters and digits, which OCR often splits
  /// into groups ("90F5 B0E8 D029 5847 263"). Whatever else follows a VIN
  /// label (a heading, an address) is not taken for one.
  static String? extractVoterId(String text) {
    final lines = _lines(text);
    for (var i = 0; i < lines.length; i++) {
      final match = _vinLabel.firstMatch(lines[i]);
      if (match == null) continue;
      final after = lines[i].substring(match.end);
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      // On the label's line, or carried over to the next.
      final vin = _vinAtStart(_value(after)) ?? _vinAtStart(_value('$after $next'));
      if (vin != null) return vin;
    }
    for (final line in lines) {
      final match = _groupedVin.firstMatch(line);
      if (match == null) continue;
      final vin = [for (var i = 1; i <= 5; i++) match.group(i)!].join().toUpperCase();
      if (RegExp(r'\d').allMatches(vin).length >= 4) return vin;
    }
    return null;
  }

  /// The VIN formed by the first groups of [value], or null unless they make
  /// exactly 19 letters and digits, with digits among them.
  static String? _vinAtStart(String value) {
    var vin = '';
    for (final group in value.toUpperCase().split(RegExp(r'[\s-]+'))) {
      final token = group.replaceAll(RegExp(r'^[.,;:]+|[.,;:]+$'), '');
      if (token.isEmpty) continue;
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(token)) break;
      vin += token;
      if (vin.length >= 19) break;
    }
    return vin.length == 19 && RegExp(r'\d').allMatches(vin).length >= 2 ? vin : null;
  }

  // --- date of birth, gender, occupation ----------------------------------------------

  // Only DATE OF BIRTH starts with DATE OF on a card, so a misread BIRTH
  // ("3IRTH") still finds it.
  static final _birthLabel = RegExp(
    r'\b(?:DATE\s+OF(?:\s+BIRTH)?|BIRTH\s*DATE|D\.?O\.?B)\b\.?',
    caseSensitive: false,
  );
  static const _months = {
    'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
    'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
  };

  /// Date of birth from a labelled line, day first as the card writes it:
  /// 14/05/1990, 14-05-1990, 14 MAY 1990 or 1990-05-14. Dates that would
  /// make the holder under 16 or over 110 are ignored.
  static DateTime? extractDateOfBirth(String text, {DateTime? today}) {
    final now = today ?? DateTime.now();
    return _labelled(text, _birthLabel, (value) {
      final upper = value.toUpperCase();
      int? day, month, year;
      if (RegExp(r'(?<!\d)(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{4})\b').firstMatch(upper)
          case final m?) {
        (day, month, year) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      } else if (RegExp(r'(?<!\d)(\d{4})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{1,2})\b').firstMatch(upper)
          case final m?) {
        (year, month, day) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      } else if (RegExp(r'(?<!\d)(\d{1,2})[\s/.\-]*([A-Z]{3})[A-Z]*\.?[\s/.,\-]*(\d{4})\b').firstMatch(upper)
          case final m?) {
        (day, month, year) = (int.parse(m[1]!), _months[m[2]!], int.parse(m[3]!));
      }
      if (day == null || month == null || year == null) return null;
      final date = DateTime(year, month, day);
      if (date.day != day || date.month != month) return null; // 31/02 is not a date
      final youngest = DateTime(now.year - 16, now.month, now.day);
      if (date.isAfter(youngest) || date.isBefore(DateTime(now.year - 110))) return null;
      return date;
    });
  }

  static final _genderLabel = RegExp(r'\b(?:GENDER|SEX)\b', caseSensitive: false);

  /// male or female, from a labelled GENDER or SEX line, or else the words
  /// Male or Female anywhere on the card (in case the label was misread).
  static String? extractGender(String text) =>
      _labelled(text, _genderLabel, (value) => _gender(value, r'MALE|FEMALE|M|F')) ??
      _gender(text, r'MALE|FEMALE');

  static String? _gender(String text, String words) =>
      switch (RegExp('\\b($words)\\b', caseSensitive: false).firstMatch(text)?.group(1)?.toUpperCase()) {
        'M' || 'MALE' => 'male',
        'F' || 'FEMALE' => 'female',
        _ => null,
      };

  static final _occupationLabel = RegExp(r'\bOCCUPATION\b', caseSensitive: false);

  static String? extractOccupation(String text) => _labelled(text, _occupationLabel, (value) {
        final cleaned = value
            .replaceAll(RegExp(r'[^A-Za-z &/.\-]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (!RegExp(r'[A-Za-z]{3,}').hasMatch(cleaned) || cleaned.length > 60) return null;
        return _titleCase(cleaned);
      });

  /// BELLO, MUSA ABDUL-MALIK -> Bello, Musa Abdul-Malik.
  static String _titleCase(String value) => value
      .toLowerCase()
      .replaceAllMapped(RegExp(r"(^|[\s'\-/])([a-z])"), (m) => '${m[1]}${m[2]!.toUpperCase()}');
}
