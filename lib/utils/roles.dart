import '../l10n/app_strings.dart';

/// The one mapping from a `profiles.role` value to its label.
/// Unknown/missing roles read as a student, the default account type.
String roleLabel(AppStrings s, String? role) => switch (role) {
      'club' => s.roleClub,
      'club_pending' => s.roleClubPending,
      'admin' => s.roleAdmin,
      'owner' => s.roleOwner,
      _ => s.roleStudent,
    };

/// Name to show for a profile row: anonymous → "Anonymous", missing
/// display name → the generic student label.
String displayNameFor(AppStrings s, Map<String, dynamic>? profile,
    {bool anonymous = false}) {
  if (anonymous) return s.anonymous;
  final name = profile?['display_name'] ?? profile?['full_name'];
  if (name is String && name.trim().isNotEmpty) return name;
  return s.roleStudent;
}
