/// Category seeds, mirrored by migration 20261026001100.
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
  CategorySeed('academic', 'Academic', 'Akademik'),
  CategorySeed('lecture', 'Lecture', 'Kuliah'),
  CategorySeed('seminar', 'Seminar', 'Seminar'),
  CategorySeed('workshop', 'Workshop', 'Bengkel'),
  CategorySeed('training', 'Training', 'Latihan'),
  CategorySeed('forum', 'Forum', 'Forum'),
  CategorySeed('conference', 'Conference', 'Konferens'),
  CategorySeed('career', 'Career', 'Kerjaya'),
  CategorySeed('internship', 'Internship', 'Latihan industri'),
  CategorySeed('entrepreneurship', 'Entrepreneurship', 'Keusahawanan'),
  CategorySeed('business', 'Business', 'Perniagaan'),
  CategorySeed('technology', 'Technology', 'Teknologi'),
  CategorySeed('ai-data', 'AI & Data', 'AI & Data'),
  CategorySeed('coding', 'Coding', 'Pengekodan'),
  CategorySeed('design', 'Design', 'Reka bentuk'),
  CategorySeed('media', 'Media', 'Media'),
  CategorySeed('photography', 'Photography', 'Fotografi'),
  CategorySeed('video', 'Video', 'Video'),
  CategorySeed('music', 'Music', 'Muzik'),
  CategorySeed('theatre', 'Theatre', 'Teater'),
  CategorySeed('dance', 'Dance', 'Tarian'),
  CategorySeed('arts', 'Arts', 'Seni'),
  CategorySeed('culture', 'Culture', 'Budaya'),
  CategorySeed('heritage', 'Heritage', 'Warisan'),
  CategorySeed('language', 'Language', 'Bahasa'),
  CategorySeed('debate', 'Debate', 'Debat'),
  CategorySeed('public-speaking', 'Public speaking', 'Pengucapan awam'),
  CategorySeed('leadership', 'Leadership', 'Kepimpinan'),
  CategorySeed('volunteering', 'Volunteering', 'Kesukarelawanan'),
  CategorySeed('community-service', 'Community service', 'Khidmat masyarakat'),
  CategorySeed('fundraising', 'Fundraising', 'Pengumpulan dana'),
  CategorySeed('charity', 'Charity', 'Amal'),
  CategorySeed('environment', 'Environment', 'Alam sekitar'),
  CategorySeed('sustainability', 'Sustainability', 'Kelestarian'),
  CategorySeed('health', 'Health', 'Kesihatan'),
  CategorySeed('mental-health', 'Mental health', 'Kesihatan mental'),
  CategorySeed('sports', 'Sports', 'Sukan'),
  CategorySeed('tournament', 'Tournament', 'Kejohanan'),
  CategorySeed('esports', 'E-sports', 'E-sukan'),
  CategorySeed('recreation', 'Recreation', 'Rekreasi'),
  CategorySeed('outdoor', 'Outdoor', 'Aktiviti luar'),
  CategorySeed('religious', 'Religious', 'Keagamaan'),
  CategorySeed('quran', 'Quran', 'Al-Quran'),
  CategorySeed('iftar', 'Iftar', 'Iftar'),
  CategorySeed('qurban', 'Qurban', 'Korban'),
  CategorySeed('bazaar', 'Bazaar', 'Bazar'),
  CategorySeed('carnival', 'Carnival', 'Karnival'),
  CategorySeed('exhibition', 'Exhibition', 'Pameran'),
  CategorySeed('networking', 'Networking', 'Networking'),
  CategorySeed('alumni', 'Alumni', 'Alumni'),
  CategorySeed('international', 'International', 'Antarabangsa'),
  CategorySeed('orientation', 'Orientation', 'Orientasi'),
  CategorySeed('club-recruitment', 'Club recruitment', 'Recruitment kelab'),
  CategorySeed('competition', 'Competition', 'Pertandingan'),
  CategorySeed('hackathon', 'Hackathon', 'Hackathon'),
  CategorySeed('cultural-night', 'Cultural night', 'Malam kebudayaan'),
];

const List<CategorySeed> kListingCategorySeeds = [
  CategorySeed('electronics', 'Electronics', 'Elektronik'),
  CategorySeed('phones', 'Phones & tablets', 'Telefon & tablet'),
  CategorySeed('computers', 'Computers', 'Komputer'),
  CategorySeed('accessories', 'Accessories', 'Aksesori'),
  CategorySeed('books', 'Books & notes', 'Buku & nota'),
  CategorySeed('stationery', 'Stationery', 'Alat tulis'),
  CategorySeed('furniture', 'Furniture', 'Perabot'),
  CategorySeed('room', 'Room & dorm', 'Bilik & asrama'),
  CategorySeed('kitchen', 'Kitchen', 'Dapur'),
  CategorySeed('clothing', 'Clothing', 'Pakaian'),
  CategorySeed('traditional-wear', 'Traditional wear', 'Pakaian tradisional'),
  CategorySeed('shoes', 'Shoes', 'Kasut'),
  CategorySeed('bags', 'Bags', 'Beg'),
  CategorySeed('sports-gear', 'Sports gear', 'Peralatan sukan'),
  CategorySeed('bicycles', 'Bicycles', 'Basikal'),
  CategorySeed('vehicles', 'Vehicles', 'Kenderaan'),
  CategorySeed('food', 'Food & drinks', 'Makanan & minuman'),
  CategorySeed('homemade-food', 'Homemade food', 'Makanan buatan sendiri'),
  CategorySeed('services', 'Services', 'Perkhidmatan'),
  CategorySeed('tickets', 'Tickets', 'Tiket'),
  CategorySeed('instruments', 'Musical instruments', 'Alat muzik'),
  CategorySeed('arts-crafts', 'Arts & crafts', 'Seni & kraf'),
  CategorySeed('gaming', 'Gaming', 'Permainan'),
  CategorySeed('collectibles', 'Collectibles', 'Barangan koleksi'),
  CategorySeed('plants', 'Plants', 'Tumbuhan'),
  CategorySeed('others', 'Others', 'Lain-lain'),
];

/// Fallback slug lists (see [CategorySeed]).
List<String> get kEventCategorySlugs => [for (final c in kEventCategorySeeds) c.slug];
List<String> get kListingCategorySlugs => [for (final c in kListingCategorySeeds) c.slug];

/// The chips shown above the event and market lists: the common
/// categories only (with All, eight chips). The rest stay searchable and,
/// for the market, in the filter sheet.
const kCommonEventCategories = [
  'academic', 'workshop', 'sports', 'religious', 'career', 'volunteering', 'competition',
];
const kCommonListingCategories = [
  'books', 'electronics', 'clothing', 'food', 'room', 'services', 'others',
];

/// How many categories one post may carry. Mirrors the DB check.
const kMaxCategoriesPerItem = 5;
