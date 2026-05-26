import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ISO-3166 code, display name, flag emoji
const _kCountries = [
  ('IN', 'India', '🇮🇳'),
  ('PK', 'Pakistan', '🇵🇰'),
  ('AU', 'Australia', '🇦🇺'),
  ('GB', 'England', '🏴󠁧󠁢󠁥󠁮󠁧󠁿'),
  ('NZ', 'New Zealand', '🇳🇿'),
  ('ZA', 'South Africa', '🇿🇦'),
  ('WI', 'West Indies', '🏝️'),
  ('LK', 'Sri Lanka', '🇱🇰'),
  ('BD', 'Bangladesh', '🇧🇩'),
  ('AF', 'Afghanistan', '🇦🇫'),
  ('ZW', 'Zimbabwe', '🇿🇼'),
  ('IE', 'Ireland', '🇮🇪'),
  ('NL', 'Netherlands', '🇳🇱'),
  ('AE', 'United Arab Emirates', '🇦🇪'),
  ('US', 'United States', '🇺🇸'),
  ('CA', 'Canada', '🇨🇦'),
  ('SC', 'Scotland', '🏴󠁧󠁢󠁳󠁣󠁴󠁿'),
  ('KE', 'Kenya', '🇰🇪'),
  ('NP', 'Nepal', '🇳🇵'),
  ('OM', 'Oman', '🇴🇲'),
  ('NG', 'Nigeria', '🇳🇬'),
  ('NM', 'Namibia', '🇳🇦'),
  ('UG', 'Uganda', '🇺🇬'),
];

class CountryPickerSheet extends StatefulWidget {
  const CountryPickerSheet({super.key});

  @override State<CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<CountryPickerSheet> {
  String _query = '';

  @override Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _kCountries
        : _kCountries
            .where((c) => c.$2.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2)),
          ),
          const Text('Select your country', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
          const SizedBox(height: 4),
          const Text('Sets your region — used for player IDs and tournament filtering',
            style: TextStyle(color: AppColors.text2, fontSize: 13)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              autofocus: false,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search, color: AppColors.text2),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final c = filtered[i];
                return ListTile(
                  leading: Text(c.$3, style: const TextStyle(fontSize: 24)),
                  title: Text(c.$2, style: const TextStyle(color: AppColors.text)),
                  subtitle: Text(c.$1, style: const TextStyle(
                    color: AppColors.text2, fontSize: 12)),
                  onTap: () => Navigator.pop(context, c.$1),
                );
              },
            ),
          ),
          const SafeArea(child: SizedBox(height: 8)),
        ]),
      ),
    );
  }
}

String countryName(String code) =>
    _kCountries.firstWhere((c) => c.$1 == code,
        orElse: () => (code, code, '🌍')).$2;

String countryFlag(String code) =>
    _kCountries.firstWhere((c) => c.$1 == code,
        orElse: () => (code, code, '🌍')).$3;
