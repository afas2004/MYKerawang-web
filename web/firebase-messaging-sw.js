// Phone notifications (push) for MYKerawang while the app is closed.
//
// A separate worker on purpose: it lives at its own scope
// (/firebase-cloud-messaging-push-scope, Firebase's default), so the
// self-removing sw_reset.js that deploy_web.bat copies over
// flutter_service_worker.js never replaces it, and it caches nothing, so it
// can never serve old app code.
//
// The sender (worker/push.py) puts the title/body in `notification` and the
// exact page in `webpush.fcm_options.link`; the Firebase SDK shows it and
// opens that page on tap. Grouped notifications share a `tag`, so the newer
// one replaces the older one on screen.
//
// Keep the version in step with firebase_core_web's
// supportedFirebaseJsSdkVersion when upgrading Firebase packages, and the
// config in step with lib/config/push_config.dart.
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDnUPOHYw7XSWBOJQgjr7ixwWe76k1ImYA',
  appId: '1:344544999110:web:ad0ab7c356a1fbe84c09c7',
  messagingSenderId: '344544999110',
  projectId: 'mykerawang-app',
});

firebase.messaging();
