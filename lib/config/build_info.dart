/// The build number this binary was compiled from.
///
/// The force-update gate compares build numbers, not semantic versions: the
/// `+45` in `0.1.0+45` is the only part that reliably increases, and comparing
/// it is an integer test rather than a parsing exercise.
///
/// Held as a constant rather than read from the bundle at runtime so the app
/// gains no dependency for one integer. build_info_test.dart reads pubspec.yaml
/// and fails if the two ever disagree, which is the only way this can go wrong.
const int kBuildNumber = 51;

/// Where the admin panel lives.
///
/// Overridable at build time so a sandbox deployment can be pointed at without
/// a code change:
///   flutter build apk --dart-define=EXODUS_ADMIN_URL=https://…
///
/// An empty value disables remote config entirely, which is the correct
/// behaviour for a build that should answer to nobody.
const String kAdminBaseUrl = String.fromEnvironment(
  'EXODUS_ADMIN_URL',
  defaultValue: '',
);
