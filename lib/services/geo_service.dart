import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────
//  GeoService — detects the user's country from their IP.
//  Uses ipapi.co (free, no key, ~100ms). Falls back to null.
// ─────────────────────────────────────────────────────────────
class GeoService {
  GeoService._();

  /// Returns ISO-3166 country code (e.g. 'IN', 'AU') or null on failure.
  static Future<String?> detectCountry() async {
    try {
      final res = await http
          .get(
            Uri.parse('https://ipapi.co/json/'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final code = data['country_code'] as String?;
        return code?.toUpperCase();
      }
    } catch (_) {}
    return null;
  }
}
