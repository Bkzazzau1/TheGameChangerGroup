import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_repository.dart';
import '../api/reference_repository.dart';
import '../media/device_media.dart';
import '../membership/pvc_recognition_service.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'polling_unit_finder_page.dart';
import 'selfie_check.dart';

/// A photo as bytes, with a file name for the upload.
typedef PhotoBytes = ({Uint8List bytes, String name});

/// What a PVC scan read off the card.
class PvcScan {
  const PvcScan({
    required this.photo,
    this.fullName,
    this.vin,
    this.delim,
    this.dateOfBirth,
    this.gender,
    this.occupation,
    this.textRead = true,
  });

  /// The fields in [text], read off [photo] by the server.
  factory PvcScan.read(PhotoBytes photo, String text) {
    final fields = PvcRecognitionService.fromText(text);
    return PvcScan(
      photo: photo,
      fullName: fields.fullName,
      vin: fields.voterId,
      delim: fields.delim,
      dateOfBirth: fields.dateOfBirth,
      gender: fields.gender,
      occupation: fields.occupation,
    );
  }

  final PhotoBytes photo;
  final String? fullName;
  final String? vin;
  final String? delim;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? occupation;

  /// False when the device could not read text (a browser): the server reads
  /// the photo instead.
  final bool textRead;
}

typedef ScanPvc = Future<PvcScan?> Function({required bool camera});
typedef TakeSelfie = Future<XFile?> Function();

/// Reads the text on a card photo on the server (replaced in tests).
typedef ReadPvcText = Future<String> Function(PhotoBytes photo);

/// The fields a browser could not read itself, read by the server. Returns the
/// scan unchanged, with the reason, when that is not possible.
Future<(PvcScan, String?)> readScanOnServer(PvcScan scan, ReadPvcText read) async {
  try {
    return (PvcScan.read(scan.photo, await read(scan.photo)), null);
  } on ApiException catch (error) {
    // 503 carries the server's own explanation; anything else (offline, too
    // many photos, an older server) gets a plain one.
    final problem = error.statusCode == 503
        ? error.message
        : error.isOffline
            ? 'Your card could not be read without a connection. Type the details from the card.'
            : 'Your card could not be read just now. Type the details from the card.';
    return (scan, problem);
  }
}

/// Scans a PVC with the device camera or gallery and reads it.
Future<PvcScan?> scanPvcWithDevice({required bool camera}) async {
  final service = PvcRecognitionService();
  final result = camera ? await service.captureAndRecognize() : await service.pickAndRecognize();
  if (result == null) return null;
  return PvcScan(
    photo: (bytes: await XFile(result.imagePath).readAsBytes(), name: result.imageName),
    fullName: result.fullName,
    vin: result.voterId,
    delim: result.delim,
    dateOfBirth: result.dateOfBirth,
    gender: result.gender,
    occupation: result.occupation,
    textRead: PvcRecognitionService.canReadText,
  );
}

/// Takes a selfie with the front camera.
Future<XFile?> takeSelfieWithDevice() => ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
      maxWidth: 1080,
    );

/// A Nigerian mobile number as +234XXXXXXXXXX, or null (matches the server).
String? normalizeNigerianPhone(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('234')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.length != 10 || !'789'.contains(digits[0])) return null;
  return '+234$digits';
}

/// A VIN as the server and USSD take it: no spaces, capital letters.
String cleanVin(String value) => value.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// A VIN has 19 letters and digits.
bool isVin(String value) => RegExp(r'^[A-Z0-9]{19}$').hasMatch(cleanVin(value));

enum _Step { phone, pvc, about, pin }

/// Joining in the app, as on USSD: the phone number first (proved by an SMS
/// code only while the server asks for one), then the PVC's VIN, polling unit
/// code and name, optional details and selfie, and a PIN.
class MemberRegistrationPage extends StatefulWidget {
  const MemberRegistrationPage({
    super.key,
    this.scanPvc = scanPvcWithDevice,
    this.takeSelfie = takeSelfieWithDevice,
    this.checkSelfie = checkSelfieOnDevice,
    this.readPvcText,
  });

  final ScanPvc scanPvc;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;

  /// Reads a card photo on the server when the device cannot (null: the
  /// server this app is connected to).
  final ReadPvcText? readPvcText;

  @override
  State<MemberRegistrationPage> createState() => _MemberRegistrationPageState();
}

class _MemberRegistrationPageState extends State<MemberRegistrationPage> {
  _Step _step = _Step.phone;
  bool _busy = false;

  // Step 1: the phone, and its SMS code while the server asks for one.
  final _phone = TextEditingController();
  bool? _phoneCodeRequired;
  String? _codeSentTo;
  DateTime? _resendAfter;
  Timer? _ticker;
  final _code = TextEditingController();

  // Step 2: the PVC.
  PhotoBytes? _pvcPhoto;
  final _name = TextEditingController();
  final _vin = TextEditingController();
  final _delim = TextEditingController();
  DelimUnit? _unit;

  /// The unit was found by name rather than from the code on the PVC.
  bool _unitFromList = false;

  /// The fields the last scan read, to say what to check and what to type.
  List<String>? _read;

  /// The server is reading the card; or why it could not.
  bool _readingCard = false;
  String? _readProblem;

  // Step 3: optional details and selfie.
  String? _gender;
  DateTime? _dateOfBirth;
  final _occupation = TextEditingController();
  final _email = TextEditingController();
  PhotoBytes? _selfie;
  SelfieCheck? _selfieCheck;
  bool _checkingSelfie = false;

  /// After two photos fail the face check, the member may keep one anyway:
  /// the check can be wrong, and a coordinator reviews the photo regardless.
  int _selfieFailures = 0;
  bool _keepSelfieAnyway = false;

  // Step 4: the PIN.
  final _pin = TextEditingController();
  final _pinAgain = TextEditingController();
  bool _consent = false;

  /// Errors by field, from the server or local checks.
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _ticker?.cancel();
    for (final controller in [_phone, _code, _name, _vin, _delim, _occupation, _email, _pin, _pinAgain]) {
      controller.dispose();
    }
    super.dispose();
  }

  MemberRepository get _members => TgcgBackend.of(context)!.member;

  void _go(_Step step) => setState(() {
        _errors = {};
        _step = step;
      });

  /// Runs [work] with the buttons off, showing server errors by their fields.
  Future<void> _whileBusy(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      await work();
    } on ApiException catch (error) {
      if (mounted) _showServerErrors(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) setState(() => _errors.remove(field));
  }

  // --- step 1 ---------------------------------------------------------------------

  String? get _normalizedPhone => normalizeNigerianPhone(_phone.text);

  bool get _codeSent => _codeSentTo != null && _codeSentTo == _normalizedPhone;

  Future<void> _phoneNext() async {
    final phone = _normalizedPhone;
    if (phone == null) {
      setState(() => _errors = {'phone_number': 'Enter a Nigerian mobile number, e.g. 0803 123 4567.'});
      return;
    }
    if (_codeSent) {
      if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
        setState(() => _errors = {'code': 'Enter the 6-digit code from the SMS.'});
        return;
      }
      _go(_Step.pvc);
      return;
    }
    await _whileBusy(() async {
      final needsCode = _phoneCodeRequired ??= await _members.phoneCodeRequired();
      if (!mounted) return;
      if (needsCode) {
        await _sendCode(phone);
      } else {
        _go(_Step.pvc);
      }
    });
  }

  Future<void> _sendCode(String phone) async {
    await _members.requestRegistrationCode(phone: phone);
    if (!mounted) return;
    setState(() {
      _codeSentTo = phone;
      _resendAfter = DateTime.now().add(const Duration(seconds: 60));
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || DateTime.now().isAfter(_resendAfter!)) timer.cancel();
      if (mounted) setState(() {});
    });
  }

  Future<void> _resendCode() async {
    final phone = _normalizedPhone;
    if (phone != null) await _whileBusy(() => _sendCode(phone));
  }

  int get _resendIn {
    final after = _resendAfter;
    if (after == null) return 0;
    final left = after.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : 0;
  }

  // --- step 2 ---------------------------------------------------------------------

  Future<void> _scan({required bool camera}) async {
    setState(() {
      _errors = {};
      _readProblem = null;
    });
    try {
      var scan = await widget.scanPvc(camera: camera);
      if (scan == null || !mounted) return;
      if (!scan.textRead) {
        // A browser cannot read the card: the server reads the photo.
        final read = widget.readPvcText ?? _members.readPvcText;
        setState(() {
          _pvcPhoto = scan!.photo;
          _readingCard = true;
          _read = null;
        });
        final (readScan, problem) = await readScanOnServer(scan, read);
        if (!mounted) return;
        setState(() {
          _readingCard = false;
          _readProblem = problem;
        });
        if (problem != null) return;
        scan = readScan;
      }
      final done = scan;
      setState(() {
        _pvcPhoto = done.photo;
        if (done.fullName != null) _name.text = done.fullName!;
        if (done.vin != null) _vin.text = done.vin!;
        if (done.delim != null) _delim.text = done.delim!;
        if (done.gender != null) _gender = done.gender;
        if (done.dateOfBirth != null) _dateOfBirth = done.dateOfBirth;
        if (done.occupation != null) _occupation.text = done.occupation!;
        _read = [
          if (done.fullName != null) 'name',
          if (done.vin != null) 'VIN',
          if (done.delim != null) _codeField,
          if (done.dateOfBirth != null) 'date of birth',
          if (done.gender != null) 'gender',
          if (done.occupation != null) 'occupation',
        ];
        if (done.delim != null) {
          _unit = null;
          _unitFromList = false;
        }
      });
      if (done.delim != null) await _lookUp();
    } catch (error) {
      if (mounted) {
        setState(() {
          _readingCard = false;
          _errors = {'pvc_image': describeDeviceError(error)};
        });
      }
    }
  }

  static const _codeField = 'polling unit code';

  Future<void> _lookUp() async {
    final delim = _delim.text.trim();
    if (delim.isEmpty) return;
    setState(() {
      _busy = true;
      _errors.remove('delim');
    });
    try {
      final unit = await TgcgBackend.of(context)!.reference.pollingUnitForDelim(delim);
      if (!mounted) return;
      setState(() {
        _unit = unit;
        _delim.text = unit.code;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _unit = null;
          _errors['delim'] = error.fieldError('delim') ?? error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// For someone who cannot read the code on their PVC: the polling unit
  /// found by name, from the state down. The server records that it was.
  Future<void> _findUnit() async {
    final place = await Navigator.of(context).push<RegistrationPlace>(
      MaterialPageRoute(builder: (_) => const PollingUnitFinderPage()),
    );
    if (place == null || !mounted) return;
    setState(() {
      _delim.text = place.code;
      _unit = null;
      _unitFromList = false;
    });
    await _lookUp();
    if (mounted && _unit != null) setState(() => _unitFromList = true);
  }

  /// Says what is missing instead of keeping Next grey; finds the polling
  /// unit when its code was typed but not looked up.
  Future<void> _pvcNext() async {
    final delim = _delim.text.trim();
    setState(() {
      _errors = {
        if (_name.text.trim().isEmpty) 'full_name': 'Enter your full name, as on the PVC.',
        if (!isVin(_vin.text)) 'vin': 'A VIN has 19 letters and digits.',
        if (delim.isEmpty)
          'delim': 'Enter the polling unit code from your PVC, or find your polling unit.',
      };
    });
    if (_unit == null && delim.isNotEmpty) await _lookUp();
    if (!mounted || _errors.isNotEmpty || _unit == null) return;
    _go(_Step.about);
  }

  // --- step 3 ---------------------------------------------------------------------

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 110);
    final lastDate = DateTime(now.year - 16, now.month, now.day);
    final birthday = DateUtils.dateOnly(_dateOfBirth ?? DateTime(now.year - 30));
    final initialDate = birthday.isBefore(firstDate)
        ? firstDate
        : birthday.isAfter(lastDate)
            ? lastDate
            : birthday;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _takeSelfie() async {
    try {
      final file = await widget.takeSelfie();
      if (file == null) return;
      final selfie = (bytes: await file.readAsBytes(), name: file.name.isEmpty ? 'selfie.jpg' : file.name);
      if (!mounted) return;
      setState(() {
        _selfie = selfie;
        _selfieCheck = null;
        _checkingSelfie = true;
        _errors.remove('photo');
      });
      final check = await _checkSelfie(file);
      if (mounted) {
        setState(() {
          _selfieCheck = check;
          _checkingSelfie = false;
          _keepSelfieAnyway = false;
          if (!check.passed) _selfieFailures++;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _errors = {'photo': describeDeviceError(error)});
    }
  }

  /// The phone's face check. If the check itself breaks, the photo goes
  /// through: it is about photo quality, and a coordinator reviews every
  /// member anyway.
  Future<SelfieCheck> _checkSelfie(XFile file) async {
    try {
      return await widget.checkSelfie(file);
    } catch (_) {
      return const SelfieCheck.notAvailable();
    }
  }

  /// A selfie that passed the face check, or that the member chose to keep.
  bool get _selfieReady =>
      _selfie != null && !_checkingSelfie && ((_selfieCheck?.passed ?? false) || _keepSelfieAnyway);

  void _removeSelfie() => setState(() {
        _selfie = null;
        _selfieCheck = null;
        _keepSelfieAnyway = false;
        _errors.remove('photo');
      });

  void _aboutNext() {
    if (_selfie != null && !_selfieReady) {
      setState(() => _errors = {'photo': 'Take the photo again, or remove it.'});
      return;
    }
    _go(_Step.pin);
  }

  // --- step 4 ---------------------------------------------------------------------

  String? get _pinError {
    final pin = _pin.text;
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return 'Choose 6 digits.';
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin) || '0123456789'.contains(pin) || '9876543210'.contains(pin)) {
      return 'This PIN is too easy to guess. Choose another.';
    }
    return null;
  }

  String? get _pinAgainError => _pinAgain.text == _pin.text ? null : 'The two PINs do not match.';

  Future<void> _pinNext() async {
    final pinError = _pinError;
    final errors = {
      if (pinError != null) 'pin': pinError,
      if (pinError == null && _pinAgainError != null) 'pin_again': _pinAgainError!,
      if (!_consent) 'consent': 'Tick the box to agree.',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final session = TgcgSession.of(context, listen: false);
    final navigator = Navigator.of(context);
    await _whileBusy(() async {
      final card = await _members.register(
        MemberRegistration(
          phoneNumber: _normalizedPhone!,
          code: _codeSent ? _code.text.trim() : '',
          vin: cleanVin(_vin.text),
          delim: _unitFromList ? '' : _delim.text.trim(),
          pollingUnit: _unitFromList ? _unit!.code : '',
          fullName: _name.text.trim(),
          gender: _gender,
          dateOfBirth: _dateOfBirth,
          occupation: _occupation.text.trim(),
          email: _email.text.trim(),
          pin: _pin.text,
          selfie: _selfieReady ? _selfie : null,
          pvcImage: _pvcPhoto,
        ),
      );
      navigator.popUntil((route) => route.isFirst);
      session.signInMember(fullName: card.fullName, membershipNumber: card.membershipNumber);
    });
  }

  /// Shows server errors next to their fields and opens the first step with one.
  void _showServerErrors(ApiException error) {
    const steps = {
      'phone_number': _Step.phone,
      'code': _Step.phone,
      'full_name': _Step.pvc,
      'vin': _Step.pvc,
      'delim': _Step.pvc,
      'polling_unit': _Step.pvc,
      'pvc_image': _Step.pvc,
      'gender': _Step.about,
      'date_of_birth': _Step.about,
      'occupation': _Step.about,
      'email': _Step.about,
      'photo': _Step.about,
      'pin': _Step.pin,
      'consent': _Step.pin,
    };
    final errors = {for (final entry in error.fieldErrors.entries) entry.key: entry.value.first};
    final step = errors.keys
        .map((field) => steps[field])
        .whereType<_Step>()
        .fold<_Step?>(null, (first, s) => first == null || s.index < first.index ? s : first);
    setState(() {
      _errors = {
        ...errors,
        // A message for no field on these screens goes at the top.
        if (step == null) 'general': errors.isEmpty ? error.message : errors.values.first,
      };
      // The server wants the phone proved by SMS after all.
      if (errors.containsKey('code')) _phoneCodeRequired = true;
      if (step != null) _step = step;
    });
  }

  // --- UI -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final titles = {
      _Step.phone: 'Your phone number',
      _Step.pvc: 'Your PVC details',
      _Step.about: 'About you (optional)',
      _Step.pin: 'Choose your PIN',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Become a member')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'STEP ${_step.index + 1} OF ${_Step.values.length}',
              style: const TextStyle(
                color: TgcgColors.accentDeep,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(titles[_step]!, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_step.index + 1) / _Step.values.length,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 18),
            if (_errors['general'] != null) _ErrorBox(_errors['general']!),
            switch (_step) {
              _Step.phone => _phoneStep(),
              _Step.pvc => _pvcStep(),
              _Step.about => _aboutStep(),
              _Step.pin => _pinStep(),
            },
          ],
        ),
      ),
    );
  }

  Widget _nav({required VoidCallback onNext, String label = 'Next'}) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Row(
          children: [
            if (_step != _Step.phone) ...[
              OutlinedButton(
                onPressed: _busy ? null : () => _go(_Step.values[_step.index - 1]),
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed: _busy || _readingCard || _checkingSelfie ? null : onNext,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(label, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      );

  Widget _phoneStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            onChanged: (_) => setState(() => _errors.remove('phone_number')),
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '0803 123 4567',
              helperText: 'You sign in with this number.',
              errorText: _errors['phone_number'],
            ),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 14),
            Text(
              'We sent a 6-digit code to $_codeSentTo. Enter it below.',
              style: const TextStyle(color: TgcgColors.muted, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _clearError('code'),
              decoration: InputDecoration(labelText: 'Code from the SMS', errorText: _errors['code']),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy || _resendIn > 0 ? null : _resendCode,
                child: Text(_resendIn > 0 ? 'Send a new code in ${_resendIn}s' : 'Send a new code'),
              ),
            ),
          ] else if (_errors['code'] != null)
            _FieldError(_errors['code']!),
          _nav(onNext: _phoneNext),
        ],
      );

  Widget _pvcStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Type the name, VIN and polling unit code from your Permanent Voter Card (PVC), '
            'or scan the card to fill them in. Check each one against the card.',
            style: TextStyle(color: TgcgColors.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (_pvcPhoto != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(_pvcPhoto!.bytes, height: 160, fit: BoxFit.cover),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || _readingCard ? null : () => _scan(camera: true),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(_pvcPhoto == null ? 'Scan PVC' : 'Scan again'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _readingCard ? null : () => _scan(camera: false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose photo'),
                ),
              ),
            ],
          ),
          if (_errors['pvc_image'] != null) _FieldError(_errors['pvc_image']!),
          if (_readingCard)
            const _Notice(
              icon: Icons.hourglass_top_rounded,
              color: TgcgColors.muted,
              text: 'Reading your card. This can take a few seconds.',
            )
          else if (_readProblem != null)
            _Notice(icon: Icons.edit_outlined, color: TgcgColors.warning, text: _readProblem!)
          else if (_read != null)
            ..._scanSummary(_read!),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _clearError('full_name'),
            decoration: InputDecoration(
              labelText: 'Full name, as on the PVC',
              errorText: _errors['full_name'],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _vin,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => _clearError('vin'),
            decoration: InputDecoration(
              labelText: 'VIN (Voter Identification Number)',
              errorText: _errors['vin'],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _delim,
            onSubmitted: (_) => _lookUp(),
            onChanged: (_) => setState(() {
              _unit = null;
              _unitFromList = false;
              _errors
                ..remove('delim')
                ..remove('polling_unit');
            }),
            decoration: InputDecoration(
              labelText: 'Polling unit code (marked CODE on the PVC)',
              hintText: '18-23-01-001',
              errorText: _errors['delim'] ?? _errors['polling_unit'],
              suffixIcon: IconButton(
                tooltip: 'Find polling unit',
                onPressed: _busy ? null : _lookUp,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy || _readingCard ? null : _findUnit,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text("Don't know the code? Find your polling unit"),
            ),
          ),
          if (_unit != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.how_to_vote_outlined, color: TgcgColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your polling unit: ${_unit!.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _nav(onNext: _pvcNext),
        ],
      );

  /// What the scan read, to check against the card, and what is left to type.
  List<Widget> _scanSummary(List<String> read) {
    if (read.isEmpty) {
      return const [
        _Notice(
          icon: Icons.error_outline_rounded,
          color: TgcgColors.warning,
          text: 'No text could be read from this photo. Scan again in good light with the card '
              'filling the frame, or type the details below.',
        ),
      ];
    }
    final missing = [
      for (final field in ['name', 'VIN', _codeField])
        if (!read.contains(field)) field,
    ];
    return [
      _Notice(
        icon: Icons.fact_check_outlined,
        color: TgcgColors.info,
        text: 'Read from your card: ${read.join(', ')}. Check each one against the card.',
      ),
      if (missing.isNotEmpty)
        _Notice(
          icon: Icons.edit_outlined,
          color: TgcgColors.warning,
          text: 'Not found on the photo: ${missing.join(', ')}. '
              'Type ${missing.length == 1 ? 'it' : 'them'} from the card.',
        ),
    ];
  }

  Widget _aboutStep() {
    final check = _selfieCheck;
    final problem = check?.problem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Gender', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: 'male', label: Text('Male')),
            ButtonSegment(value: 'female', label: Text('Female')),
          ],
          selected: {?_gender},
          onSelectionChanged: (value) => setState(() => _gender = value.firstOrNull),
        ),
        if (_errors['gender'] != null) _FieldError(_errors['gender']!),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _pickBirthday,
          icon: const Icon(Icons.cake_outlined),
          label: Text(
            _dateOfBirth == null
                ? 'Date of birth'
                : 'Born ${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
          ),
        ),
        if (_errors['date_of_birth'] != null) _FieldError(_errors['date_of_birth']!),
        const SizedBox(height: 10),
        TextField(
          controller: _occupation,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: 'Occupation', errorText: _errors['occupation']),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'Email', errorText: _errors['email']),
        ),
        const SizedBox(height: 18),
        const Text('Photo of you', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          'A clear photo of your face, like a passport photo. It goes on your membership card.',
          style: TextStyle(color: TgcgColors.muted, height: 1.4),
        ),
        const SizedBox(height: 10),
        if (_selfie != null)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(_selfie!.bytes, height: 200, fit: BoxFit.cover),
            ),
          ),
        if (_checkingSelfie)
          const _Notice(
            icon: Icons.hourglass_top_rounded,
            color: TgcgColors.muted,
            text: 'Checking the photo…',
          )
        else if (problem != null && !_keepSelfieAnyway) ...[
          _Notice(icon: Icons.error_outline_rounded, color: TgcgColors.warning, text: problem),
          if (_selfieFailures >= 2)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _keepSelfieAnyway = true;
                  _errors.remove('photo');
                }),
                child: const Text('Use this photo anyway'),
              ),
            ),
        ] else if (check != null && check.ran && problem == null)
          const _Notice(
            icon: Icons.check_circle_outline_rounded,
            color: TgcgColors.success,
            text: 'Clear photo: one face, looking at the camera.',
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _checkingSelfie ? null : _takeSelfie,
                icon: const Icon(Icons.camera_front_outlined),
                label: Text(_selfie == null ? 'Take selfie' : 'Take again'),
              ),
            ),
            if (_selfie != null) ...[
              const SizedBox(width: 10),
              TextButton(
                onPressed: _checkingSelfie ? null : _removeSelfie,
                child: const Text('Remove photo'),
              ),
            ],
          ],
        ),
        if (_errors['photo'] != null) _FieldError(_errors['photo']!),
        _nav(onNext: _aboutNext),
      ],
    );
  }

  Widget _pinStep() {
    final typedBoth = _pin.text.isNotEmpty && _pinAgain.text.length == 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'You sign in with your phone number and this 6-digit PIN. Keep it secret.',
          style: TextStyle(color: TgcgColors.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() => _errors.remove('pin')),
          decoration: InputDecoration(labelText: 'PIN', errorText: _errors['pin']),
        ),
        TextField(
          controller: _pinAgain,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() => _errors.remove('pin_again')),
          decoration: InputDecoration(
            labelText: 'PIN again',
            errorText: _errors['pin_again'] ?? (typedBoth ? _pinError ?? _pinAgainError : null),
          ),
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _consent,
          onChanged: (value) => setState(() {
            _consent = value ?? false;
            _errors.remove('consent');
          }),
          title: const Text(
            'I agree that TGCG keeps my details, photo and PVC information to manage my '
            'membership and to contact me about party activities.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        if (_errors['consent'] != null) _FieldError(_errors['consent']!),
        _nav(onNext: _pinNext, label: 'Create my membership'),
      ],
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(message, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35))),
          ],
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TgcgColors.danger.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TgcgColors.danger.withValues(alpha: .3)),
        ),
        child: Text(message),
      );
}
