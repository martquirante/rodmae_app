final class AppRuntime {
  AppRuntime._();

  static bool firebaseReady = false;
  static bool supabaseReady = false;
  static String? startupIssue;
}

final class AppStartupStatus {
  final bool firebaseReady;
  final bool supabaseReady;
  final String? issue;

  const AppStartupStatus({
    required this.firebaseReady,
    required this.supabaseReady,
    this.issue,
  });

  const AppStartupStatus.localPreview()
      : firebaseReady = false,
        supabaseReady = false,
        issue = null;
}
