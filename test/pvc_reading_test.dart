import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/membership/pvc_enrollment_page.dart';
import 'package:tgcg_emcop/tgcg/membership/pvc_recognition_service.dart';

// Card text as a phone's text reader might return it. Made up for the tests:
// no real holder's details belong in the repository.
const _card = 'INDEPENDENT NATIONAL ELECTORAL COMMISSION\n'
    'VIN: 90F5 B0E8 D029 5847 263\n'
    'DELIM: 18/23/01/001\n'
    'NAME: BELLO MUSA IBRAHIM\n'
    'DATE OF BIRTH: 14-05-1990\n'
    'GENDER: M\n'
    'OCCUPATION: CIVIL SERVANT';

void main() {
  final today = DateTime(2026, 10, 12);
  String? name(String text) => PvcRecognitionService.extractName(text);
  String? vin(String text) => PvcRecognitionService.extractVoterId(text);
  DateTime? born(String text) => PvcRecognitionService.extractDateOfBirth(text, today: today);
  String? gender(String text) => PvcRecognitionService.extractGender(text);
  String? occupation(String text) => PvcRecognitionService.extractOccupation(text);

  test('reads every labelled field on the card', () {
    expect(name(_card), 'Bello Musa Ibrahim');
    expect(vin(_card), '90F5B0E8D0295847263');
    expect(PvcRecognitionService.extractDelim(_card), '18-23-01-001');
    expect(born(_card), DateTime(1990, 5, 14));
    expect(gender(_card), 'male');
    expect(occupation(_card), 'Civil Servant');
  });

  test('reads labels that stand on their own lines', () {
    const card = 'VIN\n90F5B0E8D0295847263\nNAME\nBELLO MUSA IBRAHIM\nSEX\nF\nDOB\n14 MAY 1990';
    expect(name(card), 'Bello Musa Ibrahim');
    expect(vin(card), '90F5B0E8D0295847263');
    expect(gender(card), 'female');
    expect(born(card), DateTime(1990, 5, 14));
  });

  test('joins a surname and other names, and never guesses a name', () {
    expect(name('SURNAME: BELLO\nOTHER NAMES: MUSA IBRAHIM'), 'Bello Musa Ibrahim');
    expect(name('SURNAME BELLO FIRST NAME MUSA MIDDLE NAME IBRAHIM'), 'Bello Musa Ibrahim');
    expect(name("NAME: O'NEIL ABDUL-MALIK"), "O'Neil Abdul-Malik");
    // A surname alone is not a full name, and unlabelled lines are not read.
    expect(name('SURNAME: BELLO'), isNull);
    expect(name('INDEPENDENT NATIONAL ELECTORAL COMMISSION\nBELLO MUSA'), isNull);
    // Other names on the card are not the holder's.
    expect(name('POLLING UNIT NAME: KWARBAI PRI SCH'), isNull);
  });

  test('takes only a VIN of 19 letters and digits', () {
    // Nothing else after a VIN-like word is taken for the VIN.
    expect(vin('PERMANENT VOTER CARD NIGERIA\nVIN: 90F5 B0E8 D029 5847 263'), '90F5B0E8D0295847263');
    expect(vin('ADDRESS: 4 DIVINE MERCY STREET ZARIA\nVIN: 90F5 B0E8 D029 5847 263'), '90F5B0E8D0295847263');
    expect(vin('PERMANENT VOTER CARD NIGERIA'), isNull);
    expect(vin('VIN: 90F5 B0E8 D029'), isNull);
    // Carried over to the next line, labelled another way, or with its label misread.
    expect(vin('VIN: 90F5 B0E8 D029\n5847 263'), '90F5B0E8D0295847263');
    expect(vin('VOTER ID NO 90F5B0E8D0295847263'), '90F5B0E8D0295847263');
    expect(vin('VlN: 90F5 B0E8 D029 5847 263'), '90F5B0E8D0295847263');
  });

  test('reads dates of birth written in several ways', () {
    expect(born('DATE OF BIRTH 14/05/1990'), DateTime(1990, 5, 14));
    expect(born('D.O.B: 1990-05-14'), DateTime(1990, 5, 14));
    expect(born('DOB 4 JAN 1975'), DateTime(1975, 1, 4));
    expect(born('DATE OF BIRTH 31/02/1990'), isNull); // no such day
    expect(born('DATE OF BIRTH 14/05/2015'), isNull); // too young to vote
    expect(born('ISSUED 14/05/1990'), isNull); // not labelled as a birth date
  });

  test('reads gender and occupation only from their labels', () {
    expect(gender('GENDER: FEMALE'), 'female');
    expect(gender('SEX: X'), isNull);
    expect(gender('MALE'), isNull);
    expect(occupation('OCCUPATION: TRADER'), 'Trader');
    // A line the reader ran together stops at the next label.
    expect(occupation('OCCUPATION: FARMER ADDRESS: 4 MAIN STREET'), 'Farmer');
  });

  test('says plainly what a scan amounts to', () {
    PvcRecognitionResult scan(String text) =>
        PvcRecognitionResult(imagePath: '', imageName: 'pvc.jpg', rawText: text);
    expect(describePvcScan(scan(_card)), 'Text read from the card. Check each field against the PVC.');
    expect(describePvcScan(scan(''), canReadText: false), startsWith('Card photo attached.'));
    expect(describePvcScan(scan(''), canReadText: true), startsWith('No text could be read.'));
  });
}
