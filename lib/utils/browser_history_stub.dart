/// Non-web builds have no browser history; callers fall back to popping.
bool browserHistoryBack() => false;

/// Non-web: nothing to step forward to.
bool browserHistoryForward() => false;
