/// Category seeds, mirrored by migration 20261029000100 (which folded the
/// first, longer list from 20261026001100 into these).
///
/// The database is the source of truth (`content_categories`); these lists
/// exist so a form still has something to show when the table cannot be
/// read — offline, or in a widget test with no Supabase client.
///
/// Keep the slugs in step with the migration: they are stored on content,
/// so a typo here means a chip that matches nothing.
library;

class CategorySeed {
  final String slug;
  final String en;
  final String ms;
  const CategorySeed(this.slug, this.en, this.ms);
}

const List<CategorySeed> kEventCategorySeeds = [
  CategorySeed('academic', 'Talks & academic', 'Akademik & seminar'),
  CategorySeed('workshop', 'Workshops & training', 'Bengkel & latihan'),
  CategorySeed('career', 'Career & networking', 'Kerjaya & jaringan'),
  CategorySeed('business', 'Business & entrepreneurship', 'Perniagaan & keusahawanan'),
  CategorySeed('technology', 'Tech', 'Teknologi'),
  CategorySeed('arts', 'Arts & creative', 'Seni & kreatif'),
  CategorySeed('culture', 'Culture & heritage', 'Budaya & warisan'),
  CategorySeed('entertainment', 'Entertainment', 'Hiburan'),
  CategorySeed('games', 'Games & e-sports', 'Permainan & e-sukan'),
  CategorySeed('sports', 'Sports & outdoor', 'Sukan & aktiviti luar'),
  CategorySeed('competition', 'Competitions', 'Pertandingan'),
  CategorySeed('self-development', 'Self-development', 'Pembangunan diri'),
  CategorySeed('volunteering', 'Volunteering & charity', 'Sukarelawan & amal'),
  CategorySeed('health', 'Health & wellbeing', 'Kesihatan & kesejahteraan'),
  CategorySeed('religious', 'Religious', 'Keagamaan'),
  CategorySeed('festivals', 'Festivals, bazaars & food', 'Festival, bazar & makanan'),
  CategorySeed('kolej-life', 'Kolej life', 'Kehidupan kolej'),
];

const List<CategorySeed> kListingCategorySeeds = [
  CategorySeed('electronics', 'Electronics', 'Elektronik'),
  CategorySeed('books', 'Books & stationery', 'Buku & alat tulis'),
  CategorySeed('room', 'Room & kitchen', 'Bilik & dapur'),
  CategorySeed('clothing', 'Fashion', 'Fesyen'),
  CategorySeed('beauty', 'Beauty & personal care', 'Kecantikan & penjagaan diri'),
  CategorySeed('food', 'Food & drinks', 'Makanan & minuman'),
  CategorySeed('sports-gear', 'Sports & bicycles', 'Sukan & basikal'),
  CategorySeed('vehicles', 'Vehicles', 'Kenderaan'),
  CategorySeed('gaming', 'Gaming', 'Permainan video'),
  CategorySeed('hobbies', 'Hobbies', 'Hobi'),
  CategorySeed('services', 'Services', 'Perkhidmatan'),
  CategorySeed('tickets', 'Tickets', 'Tiket'),
  CategorySeed('others', 'Others', 'Lain-lain'),
];

/// Fallback slug lists (see [CategorySeed]).
List<String> get kEventCategorySlugs => [for (final c in kEventCategorySeeds) c.slug];
List<String> get kListingCategorySlugs => [for (final c in kListingCategorySeeds) c.slug];

/// The chips shown above the event and market lists: the common
/// categories only (with All, eight chips). The rest stay searchable and,
/// for the market, in the filter sheet.
const kCommonEventCategories = [
  'academic', 'workshop', 'sports', 'games', 'entertainment', 'religious', 'volunteering',
];
const kCommonListingCategories = [
  'books', 'electronics', 'clothing', 'food', 'room', 'services', 'others',
];

/// How many categories one post may carry. Mirrors the DB check.
const kMaxCategoriesPerItem = 5;
