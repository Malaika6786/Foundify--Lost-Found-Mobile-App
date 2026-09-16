import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a raw exception (Supabase auth/Postgrest/network/etc.) into a
/// short, plain-English message safe to show a non-technical user in a
/// SnackBar — never a raw error code, stack trace, or backend-speak like
/// "PGRST116" or "violates row-level security policy".
String friendlyError(Object error) {
  if (error is AuthException) return _friendlyAuthError(error);
  if (error is PostgrestException) return _friendlyPostgrestError(error);
  if (error is StorageException) {
    return 'Could not upload the file. Please try again.';
  }

  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection failed')) {
    return 'No internet connection. Check your network and try again.';
  }
  if (text.contains('timeoutexception') || text.contains('timed out')) {
    return 'That took too long. Please try again.';
  }
  if (text.contains('not logged in')) {
    return 'Please log in to do that.';
  }

  return 'Something went wrong. Please try again.';
}

String _friendlyAuthError(AuthException error) {
  final msg = error.message.toLowerCase();

  if (msg.contains('invalid login credentials')) {
    return 'Incorrect email or password.';
  }
  if (msg.contains('already registered') || msg.contains('already exists')) {
    return 'An account with this email already exists — try logging in instead.';
  }
  if (msg.contains('password') &&
      (msg.contains('6 characters') || msg.contains('at least'))) {
    return 'Password must be at least 6 characters.';
  }
  if (msg.contains('email') && msg.contains('invalid')) {
    return 'Enter a valid email address.';
  }
  if (msg.contains('email not confirmed')) {
    return 'Please confirm your email before logging in — check your inbox.';
  }
  if (msg.contains('rate limit') || msg.contains('too many requests')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (msg.contains('user not found')) {
    return "We couldn't find an account with that email.";
  }
  if (msg.contains('session') && msg.contains('expired')) {
    return 'Your session expired — please log in again.';
  }
  return 'Could not complete that. Please check your details and try again.';
}

String _friendlyPostgrestError(PostgrestException error) {
  final msg = error.message.toLowerCase();

  // Purpose-written messages raised by our own database triggers (e.g. the
  // tag-message rate limiter) already read fine to an end user — pass them
  // through instead of genericizing them away.
  if (error.code == 'P0001') return error.message;

  if (error.code == '23505' || msg.contains('duplicate key')) {
    return 'That already exists.';
  }
  if (error.code == '42501' ||
      msg.contains('permission denied') ||
      msg.contains('row-level security')) {
    return "You don't have permission to do that.";
  }
  if (error.code == '23503' || msg.contains('foreign key')) {
    return 'That item is no longer available.';
  }
  if (msg.contains('network') || msg.contains('failed host lookup')) {
    return 'No internet connection. Check your network and try again.';
  }
  return 'Something went wrong. Please try again.';
}
