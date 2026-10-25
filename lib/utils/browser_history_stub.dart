/// Non-web builds have no browser history; callers fall back to popping.
bool browserHistoryBack() => false;

/// Non-web: nothing to step forward to.
bool browserHistoryForward() => false;

/// Non-web: there is no history to keep tidy, so the caller launches the
/// OAuth page itself (this returns false = "not handled").
bool replaceLocationForOAuth(String url) => false;
