import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'package:mykerawang/utils/app_nav.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';

/// Where data requests go. Empty until the team confirms an address —
/// the policy then points people to Settings and the admins instead.
const kPrivacyContactEmail = '';

/// Last revision of the text below; bump it when the policy changes.
const kPrivacyPolicyUpdated = '19 Oct 2026';

/// Plain-language privacy notice (PDPA 2010). Describes what the app
/// actually stores today — keep it in step with the schema.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final sections =
        identical(s, AppStrings.ms) ? _sectionsMs() : _sectionsEn();

    return Scaffold(
      appBar: appBarConstrained(context,
          leading: const AppBackButton(), title: Text(s.social.privacyPolicy)),
      body: PageBody(
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                identical(s, AppStrings.ms)
                    ? 'Dikemas kini $kPrivacyPolicyUpdated'
                    : 'Updated $kPrivacyPolicyUpdated',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final (title, body) in sections) ...[
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String get _contactEn => kPrivacyContactEmail.isEmpty
      ? 'Use Settings → Privacy & data to download or delete your data yourself. For anything else, report it in the app or contact a MYKerawang admin.'
      : 'Use Settings → Privacy & data to download or delete your data yourself. For anything else, email $kPrivacyContactEmail.';

  static String get _contactMs => kPrivacyContactEmail.isEmpty
      ? 'Gunakan Tetapan → Privasi & data untuk memuat turun atau memadam data anda sendiri. Untuk perkara lain, laporkan dalam aplikasi atau hubungi admin MYKerawang.'
      : 'Gunakan Tetapan → Privasi & data untuk memuat turun atau memadam data anda sendiri. Untuk perkara lain, e-mel $kPrivacyContactEmail.';

  static List<(String, String)> _sectionsEn() => [
        (
          'Who we are',
          'MYKerawang is a community app for the UiTM college: a feed, a Market for buying and selling, events, and profiles you can follow. This notice explains what it stores about you and who can see it.',
        ),
        (
          'What we store',
          '• Account: your email address and sign-in details (handled by our backend provider, Supabase).\n'
              '• Profile: username, display name, bio, website, avatar and role (student or club).\n'
              '• Contact details: your WhatsApp number and DuitNow payment QR, if you add them.\n'
              '• What you create: posts, comments, Market listings, events and their photos.\n'
              '• Activity: who you follow, events you join, items you save, and your notifications.\n'
              '• Reports you file about content or users, for moderation.\n'
              'On this device we also keep your theme and language choice.',
        ),
        (
          'Who can see what',
          '• Your profile, posts, comments, listings and events are visible to other users.\n'
              '• Anonymous posts and comments hide your name from everyone except you — but admins can see who wrote them, to handle abuse.\n'
              '• Your phone number and payment QR are private. A buyer only receives them when they tap Contact on one of your listings.\n'
              '• Saved items, notifications and your email are visible only to you.\n'
              '• Admins can see reports and can hide content that breaks the rules.',
        ),
        (
          'Why we use it',
          'Only to run the app: show your content, let buyers reach sellers, send you notifications, and keep the community safe. We don\'t sell your data or use it for advertising.',
        ),
        (
          'How long we keep it',
          'Until you delete it or delete your account. Deleting your account removes your profile, posts, comments, listings, events, follows, saved items and contact details. A minimal record (account id, date and item counts — no content) is kept to show the request was carried out. Uploaded image files may take longer to be cleared from storage.',
        ),
        (
          'Your rights',
          'You can see and correct your data in Edit profile, download a copy with Download my data, and delete everything with Delete my account.',
        ),
        ('Contact', _contactEn),
      ];

  static List<(String, String)> _sectionsMs() => [
        (
          'Siapa kami',
          'MYKerawang ialah aplikasi komuniti untuk kolej UiTM: suapan, Pasar untuk jual beli, acara dan profil yang boleh diikuti. Notis ini menerangkan apa yang disimpan tentang anda dan siapa boleh melihatnya.',
        ),
        (
          'Apa yang kami simpan',
          '• Akaun: alamat e-mel dan butiran log masuk (diurus oleh penyedia backend kami, Supabase).\n'
              '• Profil: nama pengguna, nama paparan, bio, laman web, avatar dan peranan (pelajar atau kelab).\n'
              '• Maklumat hubungan: nombor WhatsApp dan QR DuitNow, jika anda menambahnya.\n'
              '• Kandungan anda: post, komen, iklan Pasar, acara dan gambarnya.\n'
              '• Aktiviti: siapa anda ikut, acara yang anda sertai, item yang anda simpan dan notifikasi anda.\n'
              '• Laporan yang anda buat tentang kandungan atau pengguna, untuk moderasi.\n'
              'Pada peranti ini kami juga simpan pilihan tema dan bahasa anda.',
        ),
        (
          'Siapa boleh lihat apa',
          '• Profil, post, komen, iklan dan acara anda boleh dilihat oleh pengguna lain.\n'
              '• Post dan komen tanpa nama menyembunyikan nama anda daripada semua orang kecuali anda — tetapi admin boleh melihat penulisnya untuk menangani penyalahgunaan.\n'
              '• Nombor telefon dan QR bayaran anda adalah peribadi. Pembeli hanya menerimanya apabila mereka menekan Hubungi pada iklan anda.\n'
              '• Item disimpan, notifikasi dan e-mel anda hanya boleh dilihat oleh anda.\n'
              '• Admin boleh melihat laporan dan menyembunyikan kandungan yang melanggar peraturan.',
        ),
        (
          'Kenapa kami menggunakannya',
          'Hanya untuk menjalankan aplikasi: memaparkan kandungan anda, membolehkan pembeli menghubungi penjual, menghantar notifikasi dan menjaga keselamatan komuniti. Kami tidak menjual data anda atau menggunakannya untuk iklan.',
        ),
        (
          'Berapa lama kami menyimpannya',
          'Sehingga anda memadamnya atau memadam akaun anda. Memadam akaun akan membuang profil, post, komen, iklan, acara, ikutan, item disimpan dan maklumat hubungan anda. Rekod minimum (id akaun, tarikh dan bilangan item — tanpa kandungan) disimpan untuk menunjukkan permintaan telah dilaksanakan. Fail gambar yang dimuat naik mungkin mengambil masa lebih lama untuk dibuang dari storan.',
        ),
        (
          'Hak anda',
          'Anda boleh melihat dan membetulkan data anda di Edit profil, memuat turun salinan dengan Muat turun data saya, dan memadam semuanya dengan Padam akaun saya.',
        ),
        ('Hubungi', _contactMs),
      ];
}
