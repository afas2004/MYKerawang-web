import 'package:firebase_core/firebase_core.dart';

/// Firebase web app "MYKerawang" (project mykerawang-app). These values are
/// public by design — they identify the app, they don't grant access.
/// Keep in step with web/firebase-messaging-sw.js.
const kFirebaseWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyDnUPOHYw7XSWBOJQgjr7ixwWe76k1ImYA',
  appId: '1:344544999110:web:ad0ab7c356a1fbe84c09c7',
  messagingSenderId: '344544999110',
  projectId: 'mykerawang-app',
  authDomain: 'mykerawang-app.firebaseapp.com',
  storageBucket: 'mykerawang-app.firebasestorage.app',
);

/// Public "Web Push certificate" key for Firebase Cloud Messaging.
///
/// Firebase console → Project settings → Cloud Messaging → Web
/// configuration → Web Push certificates → Generate key pair, then paste the
/// key here. It's a public key, safe to commit.
///
/// While empty, the app keeps phone notifications switched off and says
/// they are coming soon, instead of failing (docs/push-notifications.md).
const String kWebPushVapidKey = '';
