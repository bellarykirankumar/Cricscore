/// App environment configuration.
///
/// Build with:
///   flutter run                          → dev  (default)
///   flutter run --dart-define=ENV=dev    → dev
///   flutter build ipa --dart-define=ENV=prod → prod (App Store)
library config;

const _env = String.fromEnvironment('ENV', defaultValue: 'dev');

/// True when running the production build (App Store).
const bool isProd = _env == 'prod';

// ─── REST API ────────────────────────────────────────────────────────────────
const String apiBase = isProd
    ? 'https://j6czhcdaz8.execute-api.us-east-1.amazonaws.com/prod'
    : 'https://r78anm7dvb.execute-api.us-east-1.amazonaws.com/dev';

// ─── WebSocket (clip triggers) ───────────────────────────────────────────────
const String wsUrl = isProd
    ? 'wss://gx2b5g04zb.execute-api.us-east-1.amazonaws.com/prod'
    : 'wss://2fziydn0oj.execute-api.us-east-1.amazonaws.com/dev';

// ─── Cognito ─────────────────────────────────────────────────────────────────
const String cognitoRegion   = 'us-east-1';
const String cognitoPoolId   = isProd ? 'us-east-1_q5DAEOe9G'       : 'us-east-1_9H7UT8B1I';
const String cognitoClientId = isProd ? '2kr2g7njtctpjr7tn7mk1rq3l5' : '126l3iutfb2a6qpf2jhapligsg';
