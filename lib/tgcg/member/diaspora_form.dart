import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_repository.dart';
import '../api/reference_repository.dart';
import '../ui/tgcg_design.dart';
import 'member_registration_page.dart' show normalizeNigerianPhone;

/// Calling codes of countries where numbers are dialled at home with a 0
/// that is never part of the number from abroad, as on the server: +44 07700
/// 900123 is +44 7700 900123. In Italy or Côte d'Ivoire, for one, the 0 stays.
const _trunkZero = {
  '20',
  '27',
  '31',
  '32',
  '33',
  '41',
  '43',
  '44',
  '46',
  '49',
  '60',
  '61',
  '62',
  '63',
  '64',
  '66',
  '81',
  '82',
  '84',
  '86',
  '90',
  '91',
  '92',
  '212',
  '233',
  '234',
  '250',
  '251',
  '254',
  '255',
  '256',
  '260',
  '263',
  '353',
  '358',
  '966',
  '971',
  '972',
};

/// A number from any country written with its country code (+ or 00), as
/// the server keeps it (+447700900123), or null. Joining from the diaspora
/// asks for the code: a number written as at home abroad (07700 900123 in
/// Britain) could pass for a Nigerian one.
String? normalizeAnyPhone(String value) {
  final text = value.trim().replaceAll('(0)', '');
  var digits = text.replaceAll(RegExp(r'\D'), '');
  if (text.startsWith('00')) {
    digits = digits.substring(2);
  } else if (!text.startsWith('+')) {
    return null;
  }
  for (final size in const [2, 3]) {
    if (digits.length > size &&
        _trunkZero.contains(digits.substring(0, size)) &&
        digits[size] == '0') {
      digits = digits.substring(0, size) + digits.substring(size + 1);
      break;
    }
  }
  if (digits.startsWith('234')) return normalizeNigerianPhone(digits);
  if (digits.length < 7 || digits.length > 15 || digits.startsWith('0')) return null;
  return '+$digits';
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// What has been typed about where a member joining from the diaspora lives.
class ResidenceDraft {
  RegistrationCountry? country;
  final city = TextEditingController();
  final address = TextEditingController();

  DiasporaResidence get residence =>
      DiasporaResidence(country: country?.code ?? '', city: city.text, address: address.text);

  /// What is missing, keyed as the server keys it, with the [email] they gave.
  Map<String, String> check(String email) => {
    if (country == null) 'residence_country': 'Choose the country where you live.',
    if (city.text.trim().isEmpty) 'residence_city': 'Enter the city or town where you live.',
    if (!_emailPattern.hasMatch(email.trim())) 'email': 'Enter your email address.',
  };

  void dispose() {
    city.dispose();
    address.dispose();
  }
}

/// Where a member joining from the diaspora lives: the country, chosen from
/// the server's list, the city, the address if they wish, and their email.
class ResidenceFields extends StatelessWidget {
  const ResidenceFields({
    super.key,
    required this.draft,
    required this.email,
    this.errors = const {},
    this.onChanged,
  });

  final ResidenceDraft draft;
  final TextEditingController email;

  /// Errors by field, from the server or [ResidenceDraft.check].
  final Map<String, String> errors;
  final VoidCallback? onChanged;

  Future<void> _chooseCountry(BuildContext context) async {
    final country = await Navigator.of(
      context,
    ).push<RegistrationCountry>(MaterialPageRoute(builder: (_) => const CountryPickerPage()));
    if (country == null) return;
    draft.country = country;
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        key: const ValueKey('residence-country'),
        onTap: () => _chooseCountry(context),
        borderRadius: BorderRadius.circular(TgcgRadius.sm),
        child: InputDecorator(
          isEmpty: draft.country == null,
          decoration: InputDecoration(
            labelText: 'Country where you live',
            errorText: errors['residence_country'],
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          ),
          child: Text(draft.country?.name ?? ''),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: draft.city,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(labelText: 'City or town', errorText: errors['residence_city']),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: draft.address,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(
          labelText: 'Address (optional)',
          errorText: errors['residence_address'],
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(labelText: 'Email', errorText: errors['email']),
      ),
    ],
  );
}

/// The countries members abroad may live in, from the server, narrowed by
/// typing. Returns the chosen country.
class CountryPickerPage extends StatefulWidget {
  const CountryPickerPage({super.key});

  @override
  State<CountryPickerPage> createState() => _CountryPickerPageState();
}

class _CountryPickerPageState extends State<CountryPickerPage> {
  final _filter = TextEditingController();
  List<RegistrationCountry>? _countries;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final countries = await TgcgBackend.of(context)!.reference.registrationCountries();
      if (mounted) setState(() => _countries = countries);
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.isOffline
              ? 'No connection. Check your internet and try again.'
              : error.message,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _filter.text.toLowerCase().split(' ').where((word) => word.isNotEmpty);
    final shown = [
      for (final country in _countries ?? const <RegistrationCountry>[])
        if (words.every(country.name.toLowerCase().contains)) country,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Country where you live')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Type part of the name',
                ),
              ),
            ),
            Expanded(
              child: switch ((_error, _countries)) {
                (final error?, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _load, child: const Text('Try again')),
                      ],
                    ),
                  ),
                ),
                (_, null) => const Center(child: CircularProgressIndicator()),
                _ when shown.isEmpty => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Nothing matches "${_filter.text.trim()}".'),
                  ),
                ),
                _ => ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final country = shown[index];
                    return ListTile(
                      title: Text(
                        country.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: country.callingCode.isEmpty
                          ? null
                          : Text('+${country.callingCode}', style: TgcgType.caption),
                      onTap: () => Navigator.of(context).pop(country),
                    );
                  },
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
