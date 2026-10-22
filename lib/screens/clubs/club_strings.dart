import '../../l10n/app_strings.dart';

/// Copy for clubs: directory, club page, registration, management and
/// the admin approval tab. English and Malay; Japanese maps to English.
///
/// Usage: `context.l10n.club.follow`.
class ClubStrings {
  final String clubs;
  final String directoryTitle;
  final String directorySub;
  final String searchClubs;
  final String allCategories;
  final String noClubs;
  final String noClubsBody;
  final String noMatch;
  final String registerClub;
  final String registerIntro;
  final String clubName;
  final String handle;
  final String handleHelp;
  final String handleTooShort;
  final String handleTooLong;
  final String handleBadChars;
  final String handleTaken;
  final String category;
  final String description;
  final String proof;
  final String proofHelp;
  final String proofTooShort;
  final String nameInvalid;
  final String submitRequest;
  final String requestSent;
  final String requestSentBody;
  final String viewPage;
  final String tooManyPending;
  final String follow;
  final String following;
  final String followers;
  final String followersOne;
  final String manage;
  final String pendingBanner;
  final String rejectedBanner;
  final String suspendedBanner;
  final String pinnedAnnouncement;
  final String tabAnnouncements;
  final String tabEvents;
  final String tabMarket;
  final String tabMembers;
  final String noAnnouncements;
  final String noEvents;
  final String noListings;
  final String rolePresident;
  final String roleOfficer;
  final String roleMember;
  final String clubNotFound;
  final String clubNotFoundBody;
  final String manageTitle;
  final String pageDetails;
  final String logo;
  final String cover;
  final String changePhoto;
  final String faculty;
  final String contactEmail;
  final String emailInvalid;
  final String instagram;
  final String tiktok;
  final String website;
  final String saveChanges;
  final String saved;
  final String officers;
  final String officersHelp;
  final String addOfficer;
  final String addOfficerHint;
  final String officerAdded;
  final String userNotFound;
  final String alreadyOfficer;
  final String tooManyOfficers;
  final String remove;
  final String removeOfficerTitle;
  final String removeOfficerBody;
  final String officerRemoved;
  final String leave;
  final String leaveTitle;
  final String leaveBody;
  final String left;
  final String transfer;
  final String transferHelp;
  final String transferPick;
  final String transferTitle;
  final String transferBody;
  final String transferred;
  final String noOtherOfficers;
  final String presidentMustTransfer;
  final String notOfficer;
  final String notPresident;
  final String genericError;
  final String confirm;
  final String cancel;
  final String postAs;
  final String yourself;
  final String myClubs;
  final String statusPending;
  final String statusRejected;
  final String statusSuspended;
  final String statusActive;
  final String catAcademic;
  final String catArts;
  final String catSports;
  final String catReligious;
  final String catVolunteer;
  final String catTech;
  final String catBusiness;
  final String catOther;
  final String clubRequests;
  final String noClubRequests;
  final String proofLabel;
  final String requestedBy;
  final String approve;
  final String reject;
  final String approveTitle;
  final String approveBody;
  final String rejectTitle;
  final String approved;
  final String rejected;
  final String notPending;

  const ClubStrings({
    required this.clubs,
    required this.directoryTitle,
    required this.directorySub,
    required this.searchClubs,
    required this.allCategories,
    required this.noClubs,
    required this.noClubsBody,
    required this.noMatch,
    required this.registerClub,
    required this.registerIntro,
    required this.clubName,
    required this.handle,
    required this.handleHelp,
    required this.handleTooShort,
    required this.handleTooLong,
    required this.handleBadChars,
    required this.handleTaken,
    required this.category,
    required this.description,
    required this.proof,
    required this.proofHelp,
    required this.proofTooShort,
    required this.nameInvalid,
    required this.submitRequest,
    required this.requestSent,
    required this.requestSentBody,
    required this.viewPage,
    required this.tooManyPending,
    required this.follow,
    required this.following,
    required this.followers,
    required this.followersOne,
    required this.manage,
    required this.pendingBanner,
    required this.rejectedBanner,
    required this.suspendedBanner,
    required this.pinnedAnnouncement,
    required this.tabAnnouncements,
    required this.tabEvents,
    required this.tabMarket,
    required this.tabMembers,
    required this.noAnnouncements,
    required this.noEvents,
    required this.noListings,
    required this.rolePresident,
    required this.roleOfficer,
    required this.roleMember,
    required this.clubNotFound,
    required this.clubNotFoundBody,
    required this.manageTitle,
    required this.pageDetails,
    required this.logo,
    required this.cover,
    required this.changePhoto,
    required this.faculty,
    required this.contactEmail,
    required this.emailInvalid,
    required this.instagram,
    required this.tiktok,
    required this.website,
    required this.saveChanges,
    required this.saved,
    required this.officers,
    required this.officersHelp,
    required this.addOfficer,
    required this.addOfficerHint,
    required this.officerAdded,
    required this.userNotFound,
    required this.alreadyOfficer,
    required this.tooManyOfficers,
    required this.remove,
    required this.removeOfficerTitle,
    required this.removeOfficerBody,
    required this.officerRemoved,
    required this.leave,
    required this.leaveTitle,
    required this.leaveBody,
    required this.left,
    required this.transfer,
    required this.transferHelp,
    required this.transferPick,
    required this.transferTitle,
    required this.transferBody,
    required this.transferred,
    required this.noOtherOfficers,
    required this.presidentMustTransfer,
    required this.notOfficer,
    required this.notPresident,
    required this.genericError,
    required this.confirm,
    required this.cancel,
    required this.postAs,
    required this.yourself,
    required this.myClubs,
    required this.statusPending,
    required this.statusRejected,
    required this.statusSuspended,
    required this.statusActive,
    required this.catAcademic,
    required this.catArts,
    required this.catSports,
    required this.catReligious,
    required this.catVolunteer,
    required this.catTech,
    required this.catBusiness,
    required this.catOther,
    required this.clubRequests,
    required this.noClubRequests,
    required this.proofLabel,
    required this.requestedBy,
    required this.approve,
    required this.reject,
    required this.approveTitle,
    required this.approveBody,
    required this.rejectTitle,
    required this.approved,
    required this.rejected,
    required this.notPending,
  });

  static const en = ClubStrings(
    clubs: "Clubs",
    directoryTitle: "Clubs & societies",
    directorySub: "Find a club to follow or join.",
    searchClubs: "Search clubs",
    allCategories: "All",
    noClubs: "No clubs yet",
    noClubsBody: "Clubs appear here once an admin approves them.",
    noMatch: "No clubs match your search",
    registerClub: "Register a club",
    registerIntro: "Club pages are run by student officers — no shared passwords. An admin checks each request before the page goes live.",
    clubName: "Club name",
    handle: "Handle",
    handleHelp: "Your page will be at /c/{0}. Letters, numbers and _ only.",
    handleTooShort: "At least 3 characters.",
    handleTooLong: "At most 30 characters.",
    handleBadChars: "Only letters, numbers and _.",
    handleTaken: "That handle is taken. Try another.",
    category: "Category",
    description: "About the club",
    proof: "Proof it's an official club",
    proofHelp: "e.g. HEP registration number, advisor's name, or a link to the approval letter. Only admins see this.",
    proofTooShort: "Please give a bit more detail (10+ characters).",
    nameInvalid: "Name must be 2–80 characters.",
    submitRequest: "Send request",
    requestSent: "Request sent",
    requestSentBody: "An admin will review {0}. You'll get a notification when it's decided.",
    viewPage: "View page",
    tooManyPending: "You already have 2 requests waiting. Please wait for a decision.",
    follow: "Follow",
    following: "Following",
    followers: "{0} followers",
    followersOne: "1 follower",
    manage: "Manage",
    pendingBanner: "This page is waiting for admin approval. Only officers can see it.",
    rejectedBanner: "This request wasn't approved. You can register again with more detail.",
    suspendedBanner: "This club is suspended. Officers can't post until an admin reactivates it.",
    pinnedAnnouncement: "Pinned announcement",
    tabAnnouncements: "Announcements",
    tabEvents: "Events",
    tabMarket: "Market",
    tabMembers: "Members",
    noAnnouncements: "No announcements yet",
    noEvents: "No events yet",
    noListings: "Nothing for sale",
    rolePresident: "President",
    roleOfficer: "Officer",
    roleMember: "Member",
    clubNotFound: "Club not found",
    clubNotFoundBody: "It may have been renamed or isn't approved yet.",
    manageTitle: "Manage {0}",
    pageDetails: "Page details",
    logo: "Logo",
    cover: "Cover photo",
    changePhoto: "Change",
    faculty: "Faculty / kolej",
    contactEmail: "Contact email",
    emailInvalid: "That doesn't look like an email address.",
    instagram: "Instagram",
    tiktok: "TikTok",
    website: "Website",
    saveChanges: "Save changes",
    saved: "Page updated",
    officers: "Officers",
    officersHelp: "Officers can post, create events and sell as the club. Only the president adds or removes officers.",
    addOfficer: "Add officer",
    addOfficerHint: "Their username, e.g. @aiman",
    officerAdded: "{0} is now an officer",
    userNotFound: "No one with that username.",
    alreadyOfficer: "They're already an officer.",
    tooManyOfficers: "A club can have up to 15 officers.",
    remove: "Remove",
    removeOfficerTitle: "Remove {0} as officer?",
    removeOfficerBody: "They'll no longer be able to post as the club.",
    officerRemoved: "Officer removed",
    leave: "Leave club",
    leaveTitle: "Leave as officer?",
    leaveBody: "You'll stop being able to post as the club.",
    left: "You left the club",
    transfer: "Transfer presidency",
    transferHelp: "Hand the club to another officer. You'll stay on as an officer.",
    transferPick: "Choose the new president",
    transferTitle: "Make {0} president?",
    transferBody: "They'll manage officers from now on. You can't undo this yourself.",
    transferred: "{0} is now president",
    noOtherOfficers: "Add an officer first — presidency can only go to an officer.",
    presidentMustTransfer: "Transfer the presidency before leaving.",
    notOfficer: "Only club officers can do that.",
    notPresident: "Only the president can do that.",
    genericError: "Something went wrong. Please try again.",
    confirm: "Confirm",
    cancel: "Cancel",
    postAs: "Post as",
    yourself: "Yourself",
    myClubs: "My clubs",
    statusPending: "Pending review",
    statusRejected: "Not approved",
    statusSuspended: "Suspended",
    statusActive: "Active",
    catAcademic: "Academic",
    catArts: "Arts & culture",
    catSports: "Sports",
    catReligious: "Religious",
    catVolunteer: "Volunteering",
    catTech: "Technology",
    catBusiness: "Entrepreneurship",
    catOther: "Other",
    clubRequests: "Club requests",
    noClubRequests: "No club requests",
    proofLabel: "Proof",
    requestedBy: "Requested by {0}",
    approve: "Approve",
    reject: "Reject",
    approveTitle: "Approve {0}?",
    approveBody: "The page goes live and gets a verified badge. Its officers can post, create events and sell as the club.",
    rejectTitle: "Reject {0}?",
    approved: "Club approved — the president was notified",
    rejected: "Request rejected — the president was notified",
    notPending: "This request was already handled.",
  );

  static const ms = ClubStrings(
    clubs: "Kelab",
    directoryTitle: "Kelab & persatuan",
    directorySub: "Cari kelab untuk diikuti atau disertai.",
    searchClubs: "Cari kelab",
    allCategories: "Semua",
    noClubs: "Belum ada kelab",
    noClubsBody: "Kelab akan dipaparkan di sini selepas diluluskan admin.",
    noMatch: "Tiada kelab sepadan dengan carian anda",
    registerClub: "Daftar kelab",
    registerIntro: "Halaman kelab diurus oleh pegawai pelajar — tiada kata laluan dikongsi. Admin menyemak setiap permohonan sebelum halaman disiarkan.",
    clubName: "Nama kelab",
    handle: "Pengenal",
    handleHelp: "Halaman anda di /c/{0}. Huruf, nombor dan _ sahaja.",
    handleTooShort: "Sekurang-kurangnya 3 aksara.",
    handleTooLong: "Paling banyak 30 aksara.",
    handleBadChars: "Huruf, nombor dan _ sahaja.",
    handleTaken: "Pengenal itu sudah digunakan. Cuba yang lain.",
    category: "Kategori",
    description: "Tentang kelab",
    proof: "Bukti kelab rasmi",
    proofHelp: "cth. nombor pendaftaran HEP, nama penasihat, atau pautan surat kelulusan. Hanya admin melihat ini.",
    proofTooShort: "Sila berikan butiran lanjut (10+ aksara).",
    nameInvalid: "Nama mesti 2–80 aksara.",
    submitRequest: "Hantar permohonan",
    requestSent: "Permohonan dihantar",
    requestSentBody: "Admin akan menyemak {0}. Anda akan menerima notifikasi selepas keputusan dibuat.",
    viewPage: "Lihat halaman",
    tooManyPending: "Anda sudah ada 2 permohonan menunggu. Sila tunggu keputusan.",
    follow: "Ikuti",
    following: "Mengikuti",
    followers: "{0} pengikut",
    followersOne: "1 pengikut",
    manage: "Urus",
    pendingBanner: "Halaman ini menunggu kelulusan admin. Hanya pegawai boleh melihatnya.",
    rejectedBanner: "Permohonan ini tidak diluluskan. Anda boleh mendaftar semula dengan butiran lanjut.",
    suspendedBanner: "Kelab ini digantung. Pegawai tidak boleh menyiar sehingga admin mengaktifkannya semula.",
    pinnedAnnouncement: "Pengumuman disemat",
    tabAnnouncements: "Pengumuman",
    tabEvents: "Acara",
    tabMarket: "Pasar",
    tabMembers: "Ahli",
    noAnnouncements: "Belum ada pengumuman",
    noEvents: "Belum ada acara",
    noListings: "Tiada barang dijual",
    rolePresident: "Presiden",
    roleOfficer: "Pegawai",
    roleMember: "Ahli",
    clubNotFound: "Kelab tidak dijumpai",
    clubNotFoundBody: "Mungkin telah ditukar nama atau belum diluluskan.",
    manageTitle: "Urus {0}",
    pageDetails: "Butiran halaman",
    logo: "Logo",
    cover: "Foto muka depan",
    changePhoto: "Tukar",
    faculty: "Fakulti / kolej",
    contactEmail: "E-mel hubungan",
    emailInvalid: "Itu bukan alamat e-mel yang sah.",
    instagram: "Instagram",
    tiktok: "TikTok",
    website: "Laman web",
    saveChanges: "Simpan perubahan",
    saved: "Halaman dikemas kini",
    officers: "Pegawai",
    officersHelp: "Pegawai boleh menyiar, mencipta acara dan menjual atas nama kelab. Hanya presiden boleh menambah atau membuang pegawai.",
    addOfficer: "Tambah pegawai",
    addOfficerHint: "Nama pengguna mereka, cth. @aiman",
    officerAdded: "{0} kini pegawai",
    userNotFound: "Tiada pengguna dengan nama itu.",
    alreadyOfficer: "Mereka sudah pegawai.",
    tooManyOfficers: "Kelab boleh ada sehingga 15 pegawai.",
    remove: "Buang",
    removeOfficerTitle: "Buang {0} sebagai pegawai?",
    removeOfficerBody: "Mereka tidak lagi boleh menyiar atas nama kelab.",
    officerRemoved: "Pegawai dibuang",
    leave: "Keluar kelab",
    leaveTitle: "Keluar sebagai pegawai?",
    leaveBody: "Anda tidak lagi boleh menyiar atas nama kelab.",
    left: "Anda telah keluar kelab",
    transfer: "Serah jawatan presiden",
    transferHelp: "Serahkan kelab kepada pegawai lain. Anda kekal sebagai pegawai.",
    transferPick: "Pilih presiden baharu",
    transferTitle: "Jadikan {0} presiden?",
    transferBody: "Mereka akan mengurus pegawai mulai sekarang. Anda tidak boleh membatalkannya sendiri.",
    transferred: "{0} kini presiden",
    noOtherOfficers: "Tambah pegawai dahulu — jawatan presiden hanya boleh diserah kepada pegawai.",
    presidentMustTransfer: "Serahkan jawatan presiden sebelum keluar.",
    notOfficer: "Hanya pegawai kelab boleh berbuat demikian.",
    notPresident: "Hanya presiden boleh berbuat demikian.",
    genericError: "Ada masalah. Sila cuba lagi.",
    confirm: "Sahkan",
    cancel: "Batal",
    postAs: "Siar sebagai",
    yourself: "Diri sendiri",
    myClubs: "Kelab saya",
    statusPending: "Menunggu semakan",
    statusRejected: "Tidak diluluskan",
    statusSuspended: "Digantung",
    statusActive: "Aktif",
    catAcademic: "Akademik",
    catArts: "Seni & budaya",
    catSports: "Sukan",
    catReligious: "Keagamaan",
    catVolunteer: "Sukarelawan",
    catTech: "Teknologi",
    catBusiness: "Keusahawanan",
    catOther: "Lain-lain",
    clubRequests: "Permohonan kelab",
    noClubRequests: "Tiada permohonan kelab",
    proofLabel: "Bukti",
    requestedBy: "Dimohon oleh {0}",
    approve: "Lulus",
    reject: "Tolak",
    approveTitle: "Luluskan {0}?",
    approveBody: "Halaman disiarkan dan menerima lencana disahkan. Pegawainya boleh menyiar, mencipta acara dan menjual atas nama kelab.",
    rejectTitle: "Tolak {0}?",
    approved: "Kelab diluluskan — presiden telah dimaklumkan",
    rejected: "Permohonan ditolak — presiden telah dimaklumkan",
    notPending: "Permohonan ini sudah diuruskan.",
  );

  /// Category keys stored in clubs.category.
  static const categories = [
    'academic', 'arts', 'sports', 'religious', 'volunteer', 'tech', 'business', 'other',
  ];

  String categoryLabel(String? key) => switch (key) {
        'academic' => catAcademic,
        'arts' => catArts,
        'sports' => catSports,
        'religious' => catReligious,
        'volunteer' => catVolunteer,
        'tech' => catTech,
        'business' => catBusiness,
        null || '' => '',
        'other' => catOther,
        _ => key,
      };

  String roleLabel(String? role) => switch (role) {
        'president' => rolePresident,
        'officer' => roleOfficer,
        _ => roleMember,
      };

  String statusLabel(String? status) => switch (status) {
        'pending' => statusPending,
        'rejected' => statusRejected,
        'suspended' => statusSuspended,
        _ => statusActive,
      };

  String followerLabel(int n) => n == 1 ? followersOne : followers.fill([n]);
}

extension ClubStringsOf on AppStrings {
  /// The [ClubStrings] matching this language table.
  ClubStrings get club => identical(this, AppStrings.ms) ? ClubStrings.ms : ClubStrings.en;
}
