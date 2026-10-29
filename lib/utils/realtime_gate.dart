import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

/// What the signed-in user's live channels (notification popup stream,
/// unread badge) should do after an auth change.
enum RealtimeStep {
  /// Join (or join again).
  start,

  /// Leave: nobody is signed in.
  stop,

  /// Don't join yet: the token is expired and a refresh is on its way.
  wait,

  /// Already live on a good token.
  keep,
}

/// [event] is null for the check at start-up, before any auth event.
///
/// A session restored from storage can be hours past expiry; the client
/// refreshes it in the background and announces `tokenRefreshed`. A
/// channel joined before that fails with InvalidJWTToken and does not
/// come back by itself, so joining waits for the refresh, and every
/// refresh joins again (a channel that failed on the old token recovers;
/// one that was fine is simply replaced).
RealtimeStep realtimeStepFor(
  AuthChangeEvent? event, {
  required bool signedIn,
  required bool expired,
  required bool live,
}) {
  if (!signedIn) return RealtimeStep.stop;
  if (expired) return RealtimeStep.wait;
  if (event == AuthChangeEvent.tokenRefreshed) return RealtimeStep.start;
  return live ? RealtimeStep.keep : RealtimeStep.start;
}
