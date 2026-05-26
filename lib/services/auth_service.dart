import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────────────
//  Cognito Auth Service (no Amplify dependency)
// ─────────────────────────────────────────────────────────────

const _userPoolId    = 'us-east-1_9H7UT8B1I';
const _clientId      = '126l3iutfb2a6qpf2jhapligsg';
const _region        = 'us-east-1';
const _cognitoUrl    = 'https://cognito-idp.$_region.amazonaws.com/';
const _storage       = FlutterSecureStorage();

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override String toString() => message;
}

class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();
  AuthService._();

  // ── Sign In ───────────────────────────────────────────────
  Future<AuthUser> signIn(String email, String password) async {
    final res = await _cognitoRequest('InitiateAuth', {
      'AuthFlow': 'USER_PASSWORD_AUTH',
      'ClientId': _clientId,
      'AuthParameters': {
        'USERNAME': email,
        'PASSWORD': password,
      },
    });

    final result = res['AuthenticationResult'] as Map<String, dynamic>?;
    if (result == null) {
      if (res['ChallengeName'] == 'NEW_PASSWORD_REQUIRED') {
        throw const AuthException('NEW_PASSWORD_REQUIRED');
      }
      throw const AuthException('Authentication failed');
    }

    final idToken      = result['IdToken']      as String;
    final accessToken  = result['AccessToken']  as String;
    final refreshToken = result['RefreshToken'] as String;

    await _storage.write(key: 'id_token',      value: idToken);
    await _storage.write(key: 'access_token',  value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);

    return _parseToken(idToken);
  }

  // ── Sign Up ───────────────────────────────────────────────
  Future<void> signUp(String email, String password, String name) async {
    await _cognitoRequest('SignUp', {
      'ClientId': _clientId,
      'Username': email,
      'Password': password,
      'UserAttributes': [
        {'Name': 'email', 'Value': email},
        {'Name': 'name',  'Value': name},
      ],
    });
  }

  // ── Confirm Sign Up ───────────────────────────────────────
  Future<void> confirmSignUp(String email, String code) async {
    await _cognitoRequest('ConfirmSignUp', {
      'ClientId': _clientId,
      'Username': email,
      'ConfirmationCode': code,
    });
  }

  // ── Set New Password (for temp password users) ────────────
  Future<AuthUser> setNewPassword(
    String email, String newPassword, String session
  ) async {
    final res = await _cognitoRequest('RespondToAuthChallenge', {
      'ClientId': _clientId,
      'ChallengeName': 'NEW_PASSWORD_REQUIRED',
      'Session': session,
      'ChallengeResponses': {
        'USERNAME': email,
        'NEW_PASSWORD': newPassword,
      },
    });

    final result = res['AuthenticationResult'] as Map<String, dynamic>?;
    if (result == null) throw const AuthException('Password change failed');

    final idToken      = result['IdToken']      as String;
    final accessToken  = result['AccessToken']  as String;
    final refreshToken = result['RefreshToken'] as String;

    await _storage.write(key: 'id_token',      value: idToken);
    await _storage.write(key: 'access_token',  value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);

    return _parseToken(idToken);
  }

  // ── Restore Session ───────────────────────────────────────
  Future<AuthUser?> restoreSession() async {
    final idToken = await _storage.read(key: 'id_token');
    if (idToken == null) return null;

    try {
      final user = _parseToken(idToken);
      // Check if token is expired
      final parts = idToken.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
      ) as Map<String, dynamic>;
      final exp = (payload['exp'] as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (exp < now) {
        // Try refresh
        return await _refreshSession();
      }
      return user;
    } catch (_) {
      return null;
    }
  }

  /// Refreshes ID/access tokens when the ID token is missing, expired, or
  /// within [skewSeconds] of expiry. Safe to call before each API request so
  /// long scoring sessions keep working after the ~1h Cognito ID token TTL.
  Future<void> ensureFreshTokens({int skewSeconds = 300}) async {
    final idToken = await _storage.read(key: 'id_token');
    if (idToken == null) return;
    try {
      final parts = idToken.split('.');
      if (parts.length != 3) return;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = (payload['exp'] as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (exp < now + skewSeconds) {
        await _refreshSession();
      }
    } catch (_) {
      // If parsing fails, attempt refresh once (may clear bad state).
      await _refreshSession();
    }
  }

  // ── Refresh Token ─────────────────────────────────────────
  Future<AuthUser?> _refreshSession() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return null;

    try {
      final res = await _cognitoRequest('InitiateAuth', {
        'AuthFlow': 'REFRESH_TOKEN_AUTH',
        'ClientId': _clientId,
        'AuthParameters': {'REFRESH_TOKEN': refreshToken},
      });

      final result = res['AuthenticationResult'] as Map<String, dynamic>?;
      if (result == null) return null;

      final idToken     = result['IdToken']     as String;
      final accessToken = result['AccessToken'] as String;

      await _storage.write(key: 'id_token',     value: idToken);
      await _storage.write(key: 'access_token', value: accessToken);

      return _parseToken(idToken);
    } catch (_) {
      return null;
    }
  }

  // ── Per-user storage key helpers ─────────────────────────
  // Each user gets their own namespace so account-switching never
  // overwrites another user's country preference or owned-id cache.
  Future<String> _userKey(String base) async {
    final idToken = await _storage.read(key: 'id_token');
    if (idToken == null) return base;
    try {
      final sub = _parseToken(idToken).sub;
      return '${base}_$sub';
    } catch (_) {
      return base;
    }
  }

  // ── Country Preference ────────────────────────────────────
  Future<String?> getCountry() async =>
      _storage.read(key: await _userKey('user_country'));
  Future<void> setCountry(String code) async =>
      _storage.write(key: await _userKey('user_country'), value: code);

  // ── Local Ownership Cache ─────────────────────────────────
  Future<Set<String>> getOwnedIds() async {
    final raw = await _storage.read(key: await _userKey('owned_ids')) ?? '';
    if (raw.isEmpty) return {};
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  Future<void> claimOwnership(String resourceId) async {
    final key = await _userKey('owned_ids');
    final raw = await _storage.read(key: key) ?? '';
    final ids = raw.split(',').where((s) => s.isNotEmpty).toSet()..add(resourceId);
    await _storage.write(key: key, value: ids.join(','));
  }

  Future<bool> isLocalOwner(String resourceId) async =>
      (await getOwnedIds()).contains(resourceId);

  /// Merges [ids] into the current user's owned_ids.
  /// Called after _load() to re-hydrate from backend's createdBy field.
  Future<void> mergeOwnedIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final key = await _userKey('owned_ids');
    final raw = await _storage.read(key: key) ?? '';
    final existing = raw.split(',').where((s) => s.isNotEmpty).toSet();
    await _storage.write(key: key, value: {...existing, ...ids}.join(','));
  }

  // ── Sign Out ──────────────────────────────────────────────
  // Deletes only auth tokens. Per-user country and owned_ids keys are
  // untouched — they are namespaced by sub, so they survive for the same
  // user and are naturally invisible to any other user who logs in next.
  Future<void> signOut() async {
    await Future.wait([
      _storage.delete(key: 'id_token'),
      _storage.delete(key: 'access_token'),
      _storage.delete(key: 'refresh_token'),
    ]);
  }

  // ── Delete Account ────────────────────────────────────────
  Future<void> deleteAccount() async {
    await ensureFreshTokens();
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) throw const AuthException('Not signed in');
    await _cognitoRequest('DeleteUser', {'AccessToken': accessToken});
    await _storage.deleteAll();
  }

  // ── Parse JWT token ───────────────────────────────────────
  AuthUser _parseToken(String idToken) {
    final parts = idToken.split('.');
    if (parts.length != 3) throw const AuthException('Invalid token');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
    ) as Map<String, dynamic>;
    return AuthUser.fromJson(payload);
  }

  // ── Cognito HTTP request ──────────────────────────────────
  Future<Map<String, dynamic>> _cognitoRequest(
    String action, Map<String, dynamic> body
  ) async {
    final res = await http.post(
      Uri.parse(_cognitoUrl),
      headers: {
        'Content-Type': 'application/x-amz-json-1.1',
        'X-Amz-Target': 'AWSCognitoIdentityProviderService.$action',
      },
      body: jsonEncode(body),
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode >= 400) {
      final type    = data['__type']  as String? ?? '';
      final message = data['message'] as String? ?? 'Authentication error';

      switch (type) {
        case 'NotAuthorizedException':
          throw const AuthException('Incorrect email or password');
        case 'UserNotFoundException':
          throw const AuthException('User not found');
        case 'UsernameExistsException':
          throw const AuthException('An account with this email already exists');
        case 'CodeMismatchException':
          throw const AuthException('Incorrect verification code');
        case 'ExpiredCodeException':
          throw const AuthException('Verification code has expired');
        case 'InvalidPasswordException':
          throw AuthException(message);
        default:
          throw AuthException(message);
      }
    }

    return data;
  }
}
