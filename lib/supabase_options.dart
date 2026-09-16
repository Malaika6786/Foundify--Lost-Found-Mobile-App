// lib/supabase_options.dart
class SupabaseOptions {
  // Replace with your Supabase project URL and anon key
  static const supabaseUrl = 'https://dkainvkujpjzxngqnsrn.supabase.co';
  static const supabaseAnonKey =
      'sb_publishable_ibc33y1qGflN-awHkbVdEQ_lJqYAcLp';

  // The **Web application** OAuth Client ID from Google Cloud Console —
  // the same one entered as the Google provider's Client ID in Supabase
  // Dashboard -> Authentication -> Providers -> Google. This is a public
  // identifier (not a secret — the Client Secret stays in Supabase
  // Dashboard only), safe to ship in the app. It's what native Google
  // Sign-In uses as `serverClientId` so Supabase can verify the token.
  static const googleWebClientId =
      '309599534792-63d7ericdfi5njb98hubr5gdph01h89c.apps.googleusercontent.com';
}
