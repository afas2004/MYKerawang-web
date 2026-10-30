import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';

/// PostgREST filter for listings still for sale. `is_sold` alone lets
/// reserved items through; rows with no `status` predate the migration, so
/// they fall back to it (same rule as [ListingStatus.of]).
const kAvailableListingsFilter =
    'status.eq.available,and(status.is.null,is_sold.eq.false)';

/// `listings.status` (see 20261019002500_listing_status.sql).
enum ListingStatus {
  available,
  reserved,
  sold;

  /// Rows from before the migration (or the native cache) only carry
  /// `is_sold`; fall back to it.
  static ListingStatus of(Map<String, dynamic> listing) {
    switch (listing['status']) {
      case 'reserved':
        return ListingStatus.reserved;
      case 'sold':
        return ListingStatus.sold;
      case 'available':
        return ListingStatus.available;
    }
    return listing['is_sold'] == true ? ListingStatus.sold : ListingStatus.available;
  }

  /// Value written to the database.
  String get dbValue => name;

  String label(AppStrings s) => switch (this) {
        ListingStatus.available => s.statusAvailable,
        ListingStatus.reserved => s.statusReserved,
        ListingStatus.sold => s.sold,
      };

  /// Badge text on grid tiles and the detail hero; none while available.
  String? badge(AppStrings s) => switch (this) {
        ListingStatus.available => null,
        ListingStatus.reserved => s.statusReserved,
        ListingStatus.sold => s.sold,
      };
}
