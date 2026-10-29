import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/realtime_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

void main() {
  RealtimeStep step(AuthChangeEvent? e,
          {bool signedIn = true, bool expired = false, bool live = false}) =>
      realtimeStepFor(e, signedIn: signedIn, expired: expired, live: live);

  test('a token restored hours past expiry waits instead of joining', () {
    // Start-up, then the initial-session event, both on the stale token.
    expect(step(null, expired: true), RealtimeStep.wait);
    expect(step(AuthChangeEvent.initialSession, expired: true), RealtimeStep.wait);
  });

  test('the refresh that follows joins', () {
    expect(step(AuthChangeEvent.tokenRefreshed), RealtimeStep.start);
  });

  test('every refresh joins again, even when already live', () {
    expect(step(AuthChangeEvent.tokenRefreshed, live: true), RealtimeStep.start);
  });

  test('a good token joins once and then keeps', () {
    expect(step(null), RealtimeStep.start);
    expect(step(AuthChangeEvent.initialSession, live: true), RealtimeStep.keep);
    expect(step(AuthChangeEvent.signedIn, live: true), RealtimeStep.keep);
  });

  test('signing in as someone else joins for them', () {
    // live is per user: a different account is not live yet.
    expect(step(AuthChangeEvent.signedIn, live: false), RealtimeStep.start);
  });

  test('signing out leaves', () {
    expect(step(AuthChangeEvent.signedOut, signedIn: false), RealtimeStep.stop);
  });
}
