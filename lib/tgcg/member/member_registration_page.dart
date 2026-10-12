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
  });
  final PhotoBytes photo;
  final String? fullName;
  final String? vin;
  final String? delim;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? occupation;
}

typedef ScanPvc = Future<PvcScan?> Function({required bool camera});
typedef TakeSelfie = Future<XFile?> Function();

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
  );
}

Future<XFile?> _selfieWithDevice() => ImagePicker().pickImage(
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

enum _Step { pvc, details, phone, selfie, pin }

/// Self-registration: PVC first, then details, phone code, selfie and PIN.
class MemberRegistrationPage extends StatefulWidget {
  const MemberRegistrationPage({
    super.key,
    this.scanPvc = scanPvcWithDevice,
    this.takeSelfie = _selfieWithDevice,
    this.checkSelfie = checkSelfieOnDevice,
    this.canReadText,
  });

  final ScanPvc scanPvc;
  final TakeSelfie takeSelfie;
  final CheckSelfie checkSelfie;

  /// Whether a scan reads text off the card here (null: ask the device).
  final bool? canReadText;

  @override
  State<MemberRegistrationPage> createState() => _MemberRegistrationPageState();
}

class _MemberRegistrationPageState extends State<MemberRegistrationPage> {
  _Step _step = _Step.pvc;

  // Step 1: PVC.
  PhotoBytes? _pvcPhoto;
  final _name = TextEditingController();
  final _vin = TextEditingController();
  final _delim = TextEditingController();
  DelimUnit? _unit;
  bool _busy = false;

  /// The fields the last scan read, to say what to check and what to type.
  List<String>? _read;

  // Step 2: details.
  String? _gender;
  DateTime? _dateOfBirth;
  final _occupation = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  // Step 3: phone code.
  String? _codeSentTo;
  DateTime? _resendAfter;
  Timer? _ticker;
  final _code = TextEditingController();

  // Step 4 and 5.
  PhotoBytes? _selfie;
  SelfieCheck? _selfieCheck;
  bool _checkingSelfie = false;

  /// After two photos fail the face check, the member may keep one anyway:
  /// the check can be wrong, and a coordinator reviews the photo regardless.
  int _selfieFailures = 0;
  bool _keepSelfieAnyway = false;
  final _pin = TextEditingController();
  final _pinAgain = TextEditingController();
  bool _consent = false;

  /// Errors by field, from the server or local checks.
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _ticker?.cancel();
    for (final controller in [_name, _vin, _delim, _occupation, _email, _phone, _code, _pin, _pinAgain]) {
      controller.dispose();
    }
    super.dispose();
  }

  MemberRepository get _members => TgcgBackend.of(context)!.member;

  bool get _canReadText => widget.canReadText ?? PvcRecognitionService.canReadText;

  void _go(_Step step) => setState(() => _step = step);

  // --- step 1 ---------------------------------------------------------------------

  Future<void> _scan({required bool camera}) async {
    setState(() => _errors = {});
    try {
      final scan = await widget.scanPvc(camera: camera);
      if (scan == null || !mounted) return;
      setState(() {
        _pvcPhoto = scan.photo;
        if (scan.fullName != null) _name.text = scan.fullName!;
        if (scan.vin != null) _vin.text = scan.vin!;
        if (scan.delim != null) _delim.text = scan.delim!;
        if (scan.gender != null) _gender = scan.gender;
        if (scan.dateOfBirth != null) _dateOfBirth = scan.dateOfBirth;
        if (scan.occupation != null) _occupation.text = scan.occupation!;
        _read = [
          if (scan.fullName != null) 'name',
          if (scan.vin != null) 'VIN',
          if (scan.delim != null) 'DELIM',
          if (scan.dateOfBirth != null) 'date of birth',
          if (scan.gender != null) 'gender',
          if (scan.occupation != null) 'occupation',
        ];
        _unit = null;
      });
      if (scan.delim != null) await _lookUp();
    } catch (error) {
      if (mounted) setState(() => _errors = {'pvc_image': describeDeviceError(error)});
    }
  }

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

  bool get _pvcDone =>
      _pvcPhoto != null &&
      _name.text.trim().isNotEmpty &&
      _vin.text.trim().length >= 8 &&
      _unit != null;

  // --- step 2 ---------------------------------------------------------------------

  String? get _normalizedPhone => normalizeNigerianPhone(_phone.text);

  bool get _detailsDone => _gender != null && _normalizedPhone != null;

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 110),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  // --- step 3 ---------------------------------------------------------------------

  Future<void> _sendCode() async {
    final phone = _normalizedPhone;
    if (phone == null) return;
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      await _members.requestRegistrationCode(phone: phone, vin: _vin.text.trim());
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
    } on ApiException catch (error) {
      if (mounted) _showServerErrors(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _resendIn {
    final after = _resendAfter;
    if (after == null) return 0;
    final left = after.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : 0;
  }

  bool get _codeDone =>
      _codeSentTo == _normalizedPhone && RegExp(r'^\d{6}$').hasMatch(_code.text.trim());

  // --- step 4 ---------------------------------------------------------------------

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

  // --- step 5 ---------------------------------------------------------------------

  String? get _pinProblem {
    final pin = _pin.text;
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return 'Choose 6 digits.';
    if (RegExp(r'^(\d)\1{5}$').hasMatch(pin) || '0123456789'.contains(pin) || '9876543210'.contains(pin)) {
      return 'This PIN is too easy to guess. Choose another.';
    }
    if (_pinAgain.text != pin) return 'The two PINs do not match.';
    return null;
  }

  Future<void> _submit() async {
    final session = TgcgSession.of(context, listen: false);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final card = await _members.register(
        MemberRegistration(
          phoneNumber: _normalizedPhone!,
          code: _code.text.trim(),
          vin: _vin.text.trim(),
          delim: _delim.text.trim(),
          fullName: _name.text.trim(),
          gender: _gender!,
          dateOfBirth: _dateOfBirth,
          occupation: _occupation.text.trim(),
          email: _email.text.trim(),
          pin: _pin.text,
          selfie: _selfie!,
          pvcImage: _pvcPhoto!,
        ),
      );
      navigator.popUntil((route) => route.isFirst);
      session.signInMember(fullName: card.fullName, membershipNumber: card.membershipNumber);
    } on ApiException catch (error) {
      if (mounted) _showServerErrors(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows server errors next to their fields and opens the first step with one.
  void _showServerErrors(ApiException error) {
    const steps = {
      'full_name': _Step.pvc,
      'vin': _Step.pvc,
      'delim': _Step.pvc,
      'pvc_image': _Step.pvc,
      'phone_number': _Step.details,
      'gender': _Step.details,
      'date_of_birth': _Step.details,
      'occupation': _Step.details,
      'email': _Step.details,
      'code': _Step.phone,
      'photo': _Step.selfie,
      'pin': _Step.pin,
      'consent': _Step.pin,
    };
    final errors = {for (final entry in error.fieldErrors.entries) entry.key: entry.value.first};
    final step = errors.keys
        .map((field) => steps[field])
        .whereType<_Step>()
        .fold<_Step?>(null, (first, s) => first == null || s.index < first.index ? s : first);
    setState(() {
      _errors = errors.isEmpty ? {'general': error.message} : errors;
      if (step != null) _step = step;
    });
  }

  // --- UI -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final titles = {
      _Step.pvc: 'Scan your PVC',
      _Step.details: 'Your details',
      _Step.phone: 'Confirm your phone',
      _Step.selfie: 'Take a selfie',
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
              _Step.pvc => _pvcStep(),
              _Step.details => _detailsStep(),
              _Step.phone => _phoneStep(),
              _Step.selfie => _selfieStep(),
              _Step.pin => _pinStep(),
            },
          ],
        ),
      ),
    );
  }

  Widget _nav({required bool canContinue, required VoidCallback onNext, String label = 'Next'}) =>
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Row(
          children: [
            if (_step != _Step.pvc) ...[
              OutlinedButton(
                onPressed: _busy ? null : () => _go(_Step.values[_step.index - 1]),
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed: canContinue && !_busy ? onNext : null,
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

  Widget _pvcStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _canReadText
                ? 'Have your Permanent Voter Card (PVC) with you. Scan the front of the card: '
                    'your name, VIN and polling unit are read from it.'
                : 'Have your Permanent Voter Card (PVC) with you. Add a photo of the front of the '
                    'card, then type your name, VIN and DELIM exactly as printed on it. On this '
                    'device the app cannot read the text from the photo.',
            style: const TextStyle(color: TgcgColors.muted, height: 1.4),
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
                  onPressed: _busy ? null : () => _scan(camera: true),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(_pvcPhoto == null ? 'Scan PVC' : 'Scan again'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _scan(camera: false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose photo'),
                ),
              ),
            ],
          ),
          if (_errors['pvc_image'] != null) _FieldError(_errors['pvc_image']!),
          if (_canReadText && _read != null) ..._scanSummary(_read!),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Full name, as on the PVC',
              errorText: _errors['full_name'],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _vin,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'VIN (Voter Identification Number)',
              errorText: _errors['vin'],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _delim,
            onSubmitted: (_) => _lookUp(),
            onChanged: (_) => setState(() => _unit = null),
            decoration: InputDecoration(
              labelText: 'DELIM (polling unit code on the PVC)',
              hintText: '18/23/01/001',
              errorText: _errors['delim'],
              suffixIcon: IconButton(
                tooltip: 'Find polling unit',
                onPressed: _busy ? null : _lookUp,
                icon: const Icon(Icons.search_rounded),
              ),
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
          _nav(canContinue: _pvcDone, onNext: () => _go(_Step.details)),
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
      for (final field in ['name', 'VIN', 'DELIM'])
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

  Widget _detailsStep() => Column(
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
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '0803 123 4567',
              helperText: 'Your login. We will text a code to it.',
              errorText: _errors['phone_number'] ??
                  (_phone.text.trim().isNotEmpty && _normalizedPhone == null
                      ? 'Enter a Nigerian mobile number, e.g. 0803 123 4567.'
                      : null),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickBirthday,
            icon: const Icon(Icons.cake_outlined),
            label: Text(
              _dateOfBirth == null
                  ? 'Date of birth (optional)'
                  : 'Born ${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
            ),
          ),
          if (_errors['date_of_birth'] != null) _FieldError(_errors['date_of_birth']!),
          const SizedBox(height: 10),
          TextField(
            controller: _occupation,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Occupation (optional)',
              errorText: _errors['occupation'],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Email (optional)', errorText: _errors['email']),
          ),
          _nav(canContinue: _detailsDone, onNext: () => _go(_Step.phone)),
        ],
      );

  Widget _phoneStep() {
    final phone = _normalizedPhone ?? '';
    final sent = _codeSentTo == phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          sent
              ? 'We sent a 6-digit code to $phone. Enter it below.'
              : 'We will text a 6-digit code to $phone to confirm it is yours.',
          style: const TextStyle(color: TgcgColors.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        if (!sent)
          FilledButton.icon(
            onPressed: _busy ? null : _sendCode,
            icon: const Icon(Icons.sms_outlined),
            label: const Text('Send code'),
          )
        else ...[
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Code from the SMS', errorText: _errors['code']),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy || _resendIn > 0 ? null : _sendCode,
              child: Text(_resendIn > 0 ? 'Send a new code in ${_resendIn}s' : 'Send a new code'),
            ),
          ),
        ],
        if (_errors['phone_number'] != null) _FieldError(_errors['phone_number']!),
        _nav(canContinue: _codeDone, onNext: () => _go(_Step.selfie)),
      ],
    );
  }

  Widget _selfieStep() {
    final check = _selfieCheck;
    final problem = check?.problem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Take a clear photo of your face, like a passport photo. It goes on your '
          'membership card.',
          style: TextStyle(color: TgcgColors.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
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
                onPressed: () => setState(() => _keepSelfieAnyway = true),
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
        FilledButton.icon(
          onPressed: _checkingSelfie ? null : _takeSelfie,
          icon: const Icon(Icons.camera_front_outlined),
          label: Text(_selfie == null ? 'Take selfie' : 'Take again'),
        ),
        if (_errors['photo'] != null) _FieldError(_errors['photo']!),
        _nav(
          canContinue: _selfie != null &&
              !_checkingSelfie &&
              ((check?.passed ?? false) || _keepSelfieAnyway),
          onNext: () => _go(_Step.pin),
        ),
      ],
    );
  }

  Widget _pinStep() {
    final problem = _pin.text.isEmpty ? null : _pinProblem;
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
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'PIN', errorText: _errors['pin']),
        ),
        TextField(
          controller: _pinAgain,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'PIN again',
            errorText: _pinAgain.text.length == 6 ? problem : null,
          ),
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _consent,
          onChanged: (value) => setState(() => _consent = value ?? false),
          title: const Text(
            'I agree that TGCG keeps my details, photo and PVC information to manage my '
            'membership and to contact me about party activities.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        if (_errors['consent'] != null) _FieldError(_errors['consent']!),
        _nav(
          canContinue: _pinProblem == null && _consent,
          onNext: _submit,
          label: 'Create my membership',
        ),
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
