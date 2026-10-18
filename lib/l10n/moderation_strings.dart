import 'app_strings.dart';

/// Copy for moderation: report sheet, restriction notices, account
/// status, pins and the admin console. Kept out of app_strings.dart so
/// parallel work there doesn't collide; fold it in when convenient.
///
/// Usage: `context.l10n.mod.reportReceived`. Japanese is being dropped,
/// so `ja` reuses English.
class ModerationStrings {
  // ---- shared
  final String moderation;
  final String cancel;
  final String confirm;
  final String apply;
  final String save;
  final String ok;
  final String undo;
  final String retry;
  final String errGeneric;

  // ---- types / categories / scopes
  final String typePost;
  final String typeComment;
  final String typeEvent;
  final String typeListing;
  final String typeUser;
  final String catSpam;
  final String catScam;
  final String catHarassment;
  final String catInappropriate;
  final String catMinorSafety;
  final String catMisinformation;
  final String catOther;
  final String scopePost;
  final String scopeComment;
  final String scopeMarket;
  final String scopeEvents;
  final String scopeAccount;

  // ---- report sheet
  final String reportTitle;
  final String reportWhy;
  final String reportReceived;
  final String reportDuplicate;
  final String reportOwn;
  final String reportMissing;
  final String reportFailed;

  // ---- restriction notices
  final String cantPost;
  final String cantComment;
  final String cantSell;
  final String cantEvents;
  final String cantAccount;
  final String restrictedUntil;
  final String restrictedPermanent;
  final String restrictedReason;
  final String restrictedAuto;
  final String accountStatus;
  final String rateLimitedTitle;
  final String rateLimited;
  final String rateKindPost;
  final String rateKindComment;
  final String rateKindListing;
  final String rateKindEvent;

  // ---- account status (user side)
  final String goodStanding;
  final String goodStandingBody;
  final String sectionRestrictions;
  final String sectionDecisions;
  final String appeal;
  final String appealTitle;
  final String appealHint;
  final String appealSend;
  final String appealSent;
  final String appealDuplicate;
  final String appealNotAllowed;
  final String appealLength;
  final String appealPending;
  final String appealAccepted;
  final String appealRejected;
  final String caseHiddenPending;
  final String caseRemoved;
  final String caseWarned;
  final String caseRestored;
  final String reportedAs;
  final String contentGone;

  // ---- pins
  final String pinned;
  final String pin;
  final String unpin;
  final String pinnedFor;
  final String unpinnedDone;
  final String pinCapTitle;
  final String pinCapBody;
  final String replace;
  final String pinAnonymous;
  final String pinNotAllowed;

  // ---- admin shell
  final String adminOnly;
  final String adminOnlyBody;
  final String tabCases;
  final String tabClubs;
  final String tabAppeals;
  final String tabRestrictions;
  final String tabLog;
  final String tabSettings;
  final String openSummary;
  final String noOpenSummary;
  final String ageDay;
  final String ageHour;
  final String ageMinute;
  final String ageNow;

  // ---- cases
  final String filterActive;
  final String filterHidden;
  final String filterResolved;
  final String filterAll;
  final String allTypes;
  final String allCategories;
  final String priorityUrgent;
  final String priorityHigh;
  final String statusOpen;
  final String statusHidden;
  final String statusActioned;
  final String statusDismissed;
  final String statusClosed;
  final String decisionDismissed;
  final String decisionRestored;
  final String decisionRemoved;
  final String decisionWarned;
  final String decisionTargetDeleted;
  final String reportsCount;
  final String firstReported;
  final String anonymousAuthor;
  final String strikesCount;
  final String autoHidden;
  final String actionDismiss;
  final String actionRestore;
  final String actionRemove;
  final String actionWarn;
  final String actionRestrict;
  final String actionUnmask;
  final String reasonLabel;
  final String reasonHelp;
  final String reasonTooShort;
  final String dismissTitle;
  final String dismissBody;
  final String restoreTitle;
  final String restoreBody;
  final String removeTitle;
  final String removeBody;
  final String warnTitle;
  final String warnBody;
  final String doneDismissed;
  final String doneRestored;
  final String doneRemoved;
  final String doneWarned;
  final String doneRestricted;
  final String undone;
  final String restrictTitle;
  final String restrictWhat;
  final String restrictFor;
  final String durationDay;
  final String durationDays;
  final String durationPermanent;
  final String severeWarning;
  final String pickScope;
  final String unmaskTitle;
  final String unmaskBody;
  final String unmaskReasonHelp;
  final String unmaskResult;
  final String unmaskNone;
  final String bulkSelected;
  final String bulkDismiss;
  final String bulkRemove;
  final String bulkHint;
  final String bulkDone;
  final String noOpenCases;
  final String noOpenCasesBody;
  final String noCasesFilter;

  // ---- clubs
  final String noClubRequests;
  final String approve;
  final String reject;
  final String approveTitle;
  final String approveBody;
  final String rejectClubTitle;
  final String clubApproved;
  final String clubRejected;

  // ---- appeals
  final String noAppeals;
  final String pendingOnly;
  final String accept;
  final String acceptTitle;
  final String acceptBody;
  final String rejectAppealTitle;
  final String rejectAppealBody;
  final String noteLabel;
  final String appealAcceptedDone;
  final String appealRejectedDone;
  final String appealAbout;

  // ---- restrictions tab
  final String noRestrictions;
  final String activeOnly;
  final String lift;
  final String liftTitle;
  final String lifted;
  final String automatic;
  final String untilDate;
  final String permanent;
  final String ended;
  final String restrictSomeone;
  final String usernameLabel;
  final String userNotFound;
  final String byName;
  final String bySystem;

  // ---- log
  final String noLog;
  final String filterAction;
  final String actorAll;
  final String actorSystem;
  final String actorAdmin;
  final String actorOwner;
  final String actorUser;
  final String downloadCsv;
  final String csvDownloaded;
  final String csvCopied;

  // ---- settings
  final String settingsSaved;
  final String settingsNotSaved;
  final String sAutoHide;
  final String sPriority;
  final String sStrikeWindow;
  final String sStrikes;
  final String sAutoRestrictDays;
  final String sNewHours;
  final String sNewPosts;
  final String sNewComments;
  final String sNewListings;
  final String sNewEvents;
  final String sReporterMin;
  final String sReporterRatio;
  final String sMaxPins;
  final String sPinDays;
  final String mustBeAtLeast;
  final String mustBeRatio;

  // ---- server errors
  final String errNotAdmin;
  final String errAlreadyResolved;
  final String errCannotUndo;
  final String errProtectedUser;
  final String errSelf;
  final String errNotFound;
  final String errNoUser;
  final String errNotPending;
  final String errBulkSpamOnly;

  const ModerationStrings({
    required this.moderation,
    required this.cancel,
    required this.confirm,
    required this.apply,
    required this.save,
    required this.ok,
    required this.undo,
    required this.retry,
    required this.errGeneric,
    required this.typePost,
    required this.typeComment,
    required this.typeEvent,
    required this.typeListing,
    required this.typeUser,
    required this.catSpam,
    required this.catScam,
    required this.catHarassment,
    required this.catInappropriate,
    required this.catMinorSafety,
    required this.catMisinformation,
    required this.catOther,
    required this.scopePost,
    required this.scopeComment,
    required this.scopeMarket,
    required this.scopeEvents,
    required this.scopeAccount,
    required this.reportTitle,
    required this.reportWhy,
    required this.reportReceived,
    required this.reportDuplicate,
    required this.reportOwn,
    required this.reportMissing,
    required this.reportFailed,
    required this.cantPost,
    required this.cantComment,
    required this.cantSell,
    required this.cantEvents,
    required this.cantAccount,
    required this.restrictedUntil,
    required this.restrictedPermanent,
    required this.restrictedReason,
    required this.restrictedAuto,
    required this.accountStatus,
    required this.rateLimitedTitle,
    required this.rateLimited,
    required this.rateKindPost,
    required this.rateKindComment,
    required this.rateKindListing,
    required this.rateKindEvent,
    required this.goodStanding,
    required this.goodStandingBody,
    required this.sectionRestrictions,
    required this.sectionDecisions,
    required this.appeal,
    required this.appealTitle,
    required this.appealHint,
    required this.appealSend,
    required this.appealSent,
    required this.appealDuplicate,
    required this.appealNotAllowed,
    required this.appealLength,
    required this.appealPending,
    required this.appealAccepted,
    required this.appealRejected,
    required this.caseHiddenPending,
    required this.caseRemoved,
    required this.caseWarned,
    required this.caseRestored,
    required this.reportedAs,
    required this.contentGone,
    required this.pinned,
    required this.pin,
    required this.unpin,
    required this.pinnedFor,
    required this.unpinnedDone,
    required this.pinCapTitle,
    required this.pinCapBody,
    required this.replace,
    required this.pinAnonymous,
    required this.pinNotAllowed,
    required this.adminOnly,
    required this.adminOnlyBody,
    required this.tabCases,
    required this.tabClubs,
    required this.tabAppeals,
    required this.tabRestrictions,
    required this.tabLog,
    required this.tabSettings,
    required this.openSummary,
    required this.noOpenSummary,
    required this.ageDay,
    required this.ageHour,
    required this.ageMinute,
    required this.ageNow,
    required this.filterActive,
    required this.filterHidden,
    required this.filterResolved,
    required this.filterAll,
    required this.allTypes,
    required this.allCategories,
    required this.priorityUrgent,
    required this.priorityHigh,
    required this.statusOpen,
    required this.statusHidden,
    required this.statusActioned,
    required this.statusDismissed,
    required this.statusClosed,
    required this.decisionDismissed,
    required this.decisionRestored,
    required this.decisionRemoved,
    required this.decisionWarned,
    required this.decisionTargetDeleted,
    required this.reportsCount,
    required this.firstReported,
    required this.anonymousAuthor,
    required this.strikesCount,
    required this.autoHidden,
    required this.actionDismiss,
    required this.actionRestore,
    required this.actionRemove,
    required this.actionWarn,
    required this.actionRestrict,
    required this.actionUnmask,
    required this.reasonLabel,
    required this.reasonHelp,
    required this.reasonTooShort,
    required this.dismissTitle,
    required this.dismissBody,
    required this.restoreTitle,
    required this.restoreBody,
    required this.removeTitle,
    required this.removeBody,
    required this.warnTitle,
    required this.warnBody,
    required this.doneDismissed,
    required this.doneRestored,
    required this.doneRemoved,
    required this.doneWarned,
    required this.doneRestricted,
    required this.undone,
    required this.restrictTitle,
    required this.restrictWhat,
    required this.restrictFor,
    required this.durationDay,
    required this.durationDays,
    required this.durationPermanent,
    required this.severeWarning,
    required this.pickScope,
    required this.unmaskTitle,
    required this.unmaskBody,
    required this.unmaskReasonHelp,
    required this.unmaskResult,
    required this.unmaskNone,
    required this.bulkSelected,
    required this.bulkDismiss,
    required this.bulkRemove,
    required this.bulkHint,
    required this.bulkDone,
    required this.noOpenCases,
    required this.noOpenCasesBody,
    required this.noCasesFilter,
    required this.noClubRequests,
    required this.approve,
    required this.reject,
    required this.approveTitle,
    required this.approveBody,
    required this.rejectClubTitle,
    required this.clubApproved,
    required this.clubRejected,
    required this.noAppeals,
    required this.pendingOnly,
    required this.accept,
    required this.acceptTitle,
    required this.acceptBody,
    required this.rejectAppealTitle,
    required this.rejectAppealBody,
    required this.noteLabel,
    required this.appealAcceptedDone,
    required this.appealRejectedDone,
    required this.appealAbout,
    required this.noRestrictions,
    required this.activeOnly,
    required this.lift,
    required this.liftTitle,
    required this.lifted,
    required this.automatic,
    required this.untilDate,
    required this.permanent,
    required this.ended,
    required this.restrictSomeone,
    required this.usernameLabel,
    required this.userNotFound,
    required this.byName,
    required this.bySystem,
    required this.noLog,
    required this.filterAction,
    required this.actorAll,
    required this.actorSystem,
    required this.actorAdmin,
    required this.actorOwner,
    required this.actorUser,
    required this.downloadCsv,
    required this.csvDownloaded,
    required this.csvCopied,
    required this.settingsSaved,
    required this.settingsNotSaved,
    required this.sAutoHide,
    required this.sPriority,
    required this.sStrikeWindow,
    required this.sStrikes,
    required this.sAutoRestrictDays,
    required this.sNewHours,
    required this.sNewPosts,
    required this.sNewComments,
    required this.sNewListings,
    required this.sNewEvents,
    required this.sReporterMin,
    required this.sReporterRatio,
    required this.sMaxPins,
    required this.sPinDays,
    required this.mustBeAtLeast,
    required this.mustBeRatio,
    required this.errNotAdmin,
    required this.errAlreadyResolved,
    required this.errCannotUndo,
    required this.errProtectedUser,
    required this.errSelf,
    required this.errNotFound,
    required this.errNoUser,
    required this.errNotPending,
    required this.errBulkSpamOnly,
  });

  static const en = ModerationStrings(
    moderation: "Moderation",
    cancel: "Cancel",
    confirm: "Confirm",
    apply: "Apply",
    save: "Save",
    ok: "OK",
    undo: "Undo",
    retry: "Retry",
    errGeneric: "Something went wrong. Please try again.",
    typePost: "Post",
    typeComment: "Comment",
    typeEvent: "Event",
    typeListing: "Listing",
    typeUser: "Profile",
    catSpam: "Spam",
    catScam: "Scam or fraud",
    catHarassment: "Hate speech or harassment",
    catInappropriate: "Sexual or inappropriate content",
    catMinorSafety: "Puts a minor at risk",
    catMisinformation: "Misinformation",
    catOther: "Something else",
    scopePost: "Posting",
    scopeComment: "Commenting",
    scopeMarket: "Selling in the Market",
    scopeEvents: "Creating or joining events",
    scopeAccount: "Whole account (every action)",
    reportTitle: "Report",
    reportWhy: "What's wrong with it?",
    reportReceived: "Report received. Thanks — we'll let you know when it's reviewed.",
    reportDuplicate: "You've already reported this. We'll let you know when it's reviewed.",
    reportOwn: "You can't report your own content.",
    reportMissing: "This is no longer available.",
    reportFailed: "Couldn't send your report. Check your connection.",
    cantPost: "You can't post right now",
    cantComment: "You can't comment right now",
    cantSell: "You can't sell in the Market right now",
    cantEvents: "You can't create or join events right now",
    cantAccount: "Your account is restricted",
    restrictedUntil: "This ends on {0}.",
    restrictedPermanent: "This restriction is permanent.",
    restrictedReason: "Reason: {0}",
    restrictedAuto: "Applied automatically after several upheld reports.",
    accountStatus: "Account status",
    rateLimitedTitle: "Slow down a little",
    rateLimited: "New accounts can {0} up to {1} times an hour during their first {2} hours. Please try again later.",
    rateKindPost: "post",
    rateKindComment: "comment",
    rateKindListing: "list items",
    rateKindEvent: "create events",
    goodStanding: "Your account is in good standing",
    goodStandingBody: "No restrictions and no recent decisions about your content.",
    sectionRestrictions: "Restrictions",
    sectionDecisions: "Decisions about your content",
    appeal: "Appeal",
    appealTitle: "Appeal this decision",
    appealHint: "Explain why you think this was a mistake.",
    appealSend: "Send appeal",
    appealSent: "Appeal sent. An admin will review it and you'll get a notification.",
    appealDuplicate: "You've already appealed this decision.",
    appealNotAllowed: "This decision can no longer be appealed.",
    appealLength: "Write between 10 and 2000 characters.",
    appealPending: "Appeal pending",
    appealAccepted: "Appeal accepted",
    appealRejected: "Appeal not accepted",
    caseHiddenPending: "Hidden while an admin reviews reports",
    caseRemoved: "Removed",
    caseWarned: "Warning",
    caseRestored: "Restored after review",
    reportedAs: "Reported as: {0}",
    contentGone: "This content has been deleted.",
    pinned: "Pinned",
    pin: "Pin to top",
    unpin: "Unpin",
    pinnedFor: "Pinned to the top for {0} days",
    unpinnedDone: "Unpinned",
    pinCapTitle: "Pin limit reached",
    pinCapBody: "A club can have {0} pinned post at a time. Replace “{1}” with this one?",
    replace: "Replace",
    pinAnonymous: "Anonymous posts can't be pinned.",
    pinNotAllowed: "Only clubs (on their own posts) and admins can pin.",
    adminOnly: "Admins only",
    adminOnlyBody: "This page is for MYKerawang moderators.",
    tabCases: "Cases",
    tabClubs: "Club approvals",
    tabAppeals: "Appeals",
    tabRestrictions: "Restrictions",
    tabLog: "Log",
    tabSettings: "Settings",
    openSummary: "{0} open · oldest waiting {1}",
    noOpenSummary: "No open cases",
    ageDay: "d",
    ageHour: "h",
    ageMinute: "m",
    ageNow: "<1m",
    filterActive: "Open",
    filterHidden: "Hidden",
    filterResolved: "Resolved",
    filterAll: "All",
    allTypes: "All types",
    allCategories: "All categories",
    priorityUrgent: "Urgent",
    priorityHigh: "High",
    statusOpen: "Open",
    statusHidden: "Hidden — pending review",
    statusActioned: "Actioned",
    statusDismissed: "Dismissed",
    statusClosed: "Closed",
    decisionDismissed: "No violation",
    decisionRestored: "Restored",
    decisionRemoved: "Removed",
    decisionWarned: "Warned",
    decisionTargetDeleted: "Deleted by author",
    reportsCount: "{0} reports · {1} counted",
    firstReported: "First reported {0}",
    anonymousAuthor: "Anonymous author",
    strikesCount: "{0} recent strikes",
    autoHidden: "Auto-hidden",
    actionDismiss: "Dismiss",
    actionRestore: "Restore",
    actionRemove: "Remove",
    actionWarn: "Warn",
    actionRestrict: "Restrict",
    actionUnmask: "Reveal author",
    reasonLabel: "Reason (required)",
    reasonHelp: "Kept in the log. Removals and warnings show it to the author.",
    reasonTooShort: "Please give a reason.",
    dismissTitle: "Dismiss these reports?",
    dismissBody: "No rule was broken. Reporters are told it was reviewed.",
    restoreTitle: "Restore this {0}?",
    restoreBody: "It becomes visible again, the author is told, and reporters hear it was reviewed.",
    removeTitle: "Remove this {0}?",
    removeBody: "It stays hidden. The author gets your reason and a strike. This can't be undone, but they can appeal.",
    warnTitle: "Warn the author?",
    warnBody: "The author gets your reason and a strike. This can't be undone, but they can appeal.",
    doneDismissed: "Reports dismissed",
    doneRestored: "Restored",
    doneRemoved: "Removed — author notified",
    doneWarned: "Author warned",
    doneRestricted: "Restriction applied — user notified",
    undone: "Undone",
    restrictTitle: "Restrict user",
    restrictWhat: "What can't they do?",
    restrictFor: "For how long?",
    durationDay: "1 day",
    durationDays: "{0} days",
    durationPermanent: "Permanent",
    severeWarning: "Permanent and whole-account restrictions are serious. Make sure this is right.",
    pickScope: "Pick at least one.",
    unmaskTitle: "Reveal the anonymous author?",
    unmaskBody: "Only for safety or legal reasons. Your reason is logged and every admin can read it.",
    unmaskReasonHelp: "At least 10 characters.",
    unmaskResult: "Author: {0} (@{1})",
    unmaskNone: "The author's account no longer exists.",
    bulkSelected: "{0} selected",
    bulkDismiss: "Dismiss selected",
    bulkRemove: "Remove selected",
    bulkHint: "Bulk actions are only for spam.",
    bulkDone: "{0} cases resolved",
    noOpenCases: "No open cases",
    noOpenCasesBody: "Nothing is waiting for review.",
    noCasesFilter: "No cases match these filters.",
    noClubRequests: "No club requests",
    approve: "Approve",
    reject: "Reject",
    approveTitle: "Approve {0} as a club?",
    approveBody: "They become a verified club and can pin an announcement.",
    rejectClubTitle: "Reject this club request?",
    clubApproved: "Club approved — they've been notified",
    clubRejected: "Request rejected — they've been notified",
    noAppeals: "No pending appeals",
    pendingOnly: "Pending only",
    accept: "Accept",
    acceptTitle: "Accept this appeal?",
    acceptBody: "The decision is reversed (content restored or restriction lifted) and the user is told.",
    rejectAppealTitle: "Reject this appeal?",
    rejectAppealBody: "The decision stands. The user sees your note.",
    noteLabel: "Note to the user (required)",
    appealAcceptedDone: "Appeal accepted — user notified",
    appealRejectedDone: "Appeal rejected — user notified",
    appealAbout: "Appealing",
    noRestrictions: "No active restrictions",
    activeOnly: "Active only",
    lift: "Lift early",
    liftTitle: "Lift this restriction?",
    lifted: "Restriction lifted — user notified",
    automatic: "Automatic",
    untilDate: "Until {0}",
    permanent: "Permanent",
    ended: "Ended",
    restrictSomeone: "Restrict a user",
    usernameLabel: "Username",
    userNotFound: "No user with that username.",
    byName: "By {0}",
    bySystem: "By the system",
    noLog: "No log entries",
    filterAction: "Filter by action",
    actorAll: "Everyone",
    actorSystem: "System",
    actorAdmin: "Admins",
    actorOwner: "Owner",
    actorUser: "Users",
    downloadCsv: "Download CSV",
    csvDownloaded: "CSV downloaded",
    csvCopied: "CSV copied to the clipboard",
    settingsSaved: "Settings saved",
    settingsNotSaved: "Not saved — only the owner can change these.",
    sAutoHide: "Distinct reporters before auto-hide",
    sPriority: "Hidden on the first report",
    sStrikeWindow: "Strike window (days)",
    sStrikes: "Strikes before an automatic restriction",
    sAutoRestrictDays: "Automatic restriction length (days)",
    sNewHours: "New-account period (hours)",
    sNewPosts: "New accounts: posts per hour",
    sNewComments: "New accounts: comments per hour",
    sNewListings: "New accounts: listings per hour",
    sNewEvents: "New accounts: events per hour",
    sReporterMin: "Reporter quality: resolved reports before it applies",
    sReporterRatio: "Ignore reporters whose dismissed share is above (0–1)",
    sMaxPins: "Pinned posts per club",
    sPinDays: "Pin length (days)",
    mustBeAtLeast: "Enter a whole number of at least {0}",
    mustBeRatio: "Enter a number from 0 to 1",
    errNotAdmin: "You don't have admin access.",
    errAlreadyResolved: "Someone already handled this. The list has been refreshed.",
    errCannotUndo: "It's too late to undo this.",
    errProtectedUser: "Only the owner can restrict an admin.",
    errSelf: "You can't restrict yourself.",
    errNotFound: "This item no longer exists.",
    errNoUser: "The author can't be identified (account deleted).",
    errNotPending: "This request was already handled.",
    errBulkSpamOnly: "Bulk actions only work on cases reported solely as spam.",
  );

  static const ms = ModerationStrings(
    moderation: "Moderasi",
    cancel: "Batal",
    confirm: "Sahkan",
    apply: "Guna",
    save: "Simpan",
    ok: "OK",
    undo: "Buat asal",
    retry: "Cuba lagi",
    errGeneric: "Ada masalah. Sila cuba lagi.",
    typePost: "Siaran",
    typeComment: "Komen",
    typeEvent: "Acara",
    typeListing: "Barang",
    typeUser: "Profil",
    catSpam: "Spam",
    catScam: "Penipuan",
    catHarassment: "Ucapan kebencian atau gangguan",
    catInappropriate: "Kandungan seksual atau tidak sesuai",
    catMinorSafety: "Membahayakan kanak-kanak",
    catMisinformation: "Maklumat palsu",
    catOther: "Lain-lain",
    scopePost: "Menyiarkan",
    scopeComment: "Mengomen",
    scopeMarket: "Menjual di Pasar",
    scopeEvents: "Mencipta atau menyertai acara",
    scopeAccount: "Seluruh akaun (semua tindakan)",
    reportTitle: "Lapor",
    reportWhy: "Apa masalahnya?",
    reportReceived: "Laporan diterima. Terima kasih — kami akan maklumkan selepas ia disemak.",
    reportDuplicate: "Anda sudah melaporkan ini. Kami akan maklumkan selepas ia disemak.",
    reportOwn: "Anda tidak boleh melaporkan kandungan sendiri.",
    reportMissing: "Kandungan ini tiada lagi.",
    reportFailed: "Laporan tidak dapat dihantar. Semak sambungan anda.",
    cantPost: "Anda tidak boleh menyiarkan buat masa ini",
    cantComment: "Anda tidak boleh mengomen buat masa ini",
    cantSell: "Anda tidak boleh menjual di Pasar buat masa ini",
    cantEvents: "Anda tidak boleh mencipta atau menyertai acara buat masa ini",
    cantAccount: "Akaun anda disekat",
    restrictedUntil: "Sekatan ini tamat pada {0}.",
    restrictedPermanent: "Sekatan ini kekal.",
    restrictedReason: "Sebab: {0}",
    restrictedAuto: "Dikenakan secara automatik selepas beberapa laporan disahkan.",
    accountStatus: "Status akaun",
    rateLimitedTitle: "Perlahan sedikit",
    rateLimited: "Akaun baharu boleh {0} sehingga {1} kali sejam dalam {2} jam pertama. Sila cuba sebentar lagi.",
    rateKindPost: "menyiarkan",
    rateKindComment: "mengomen",
    rateKindListing: "menyenaraikan barang",
    rateKindEvent: "mencipta acara",
    goodStanding: "Akaun anda dalam keadaan baik",
    goodStandingBody: "Tiada sekatan dan tiada keputusan terkini tentang kandungan anda.",
    sectionRestrictions: "Sekatan",
    sectionDecisions: "Keputusan tentang kandungan anda",
    appeal: "Rayu",
    appealTitle: "Rayu keputusan ini",
    appealHint: "Terangkan mengapa anda rasa ini satu kesilapan.",
    appealSend: "Hantar rayuan",
    appealSent: "Rayuan dihantar. Admin akan menyemaknya dan anda akan menerima notifikasi.",
    appealDuplicate: "Anda sudah merayu keputusan ini.",
    appealNotAllowed: "Keputusan ini tidak boleh dirayu lagi.",
    appealLength: "Tulis antara 10 hingga 2000 aksara.",
    appealPending: "Rayuan menunggu",
    appealAccepted: "Rayuan diterima",
    appealRejected: "Rayuan tidak diterima",
    caseHiddenPending: "Disembunyikan semasa admin menyemak laporan",
    caseRemoved: "Dibuang",
    caseWarned: "Amaran",
    caseRestored: "Dipulihkan selepas semakan",
    reportedAs: "Dilaporkan sebagai: {0}",
    contentGone: "Kandungan ini telah dipadam.",
    pinned: "Disemat",
    pin: "Semat di atas",
    unpin: "Nyahsemat",
    pinnedFor: "Disemat di atas selama {0} hari",
    unpinnedDone: "Dinyahsemat",
    pinCapTitle: "Had semat dicapai",
    pinCapBody: "Kelab boleh menyemat {0} siaran pada satu masa. Gantikan “{1}” dengan siaran ini?",
    replace: "Ganti",
    pinAnonymous: "Siaran tanpa nama tidak boleh disemat.",
    pinNotAllowed: "Hanya kelab (siaran sendiri) dan admin boleh menyemat.",
    adminOnly: "Admin sahaja",
    adminOnlyBody: "Halaman ini untuk moderator MYKerawang.",
    tabCases: "Kes",
    tabClubs: "Kelulusan kelab",
    tabAppeals: "Rayuan",
    tabRestrictions: "Sekatan",
    tabLog: "Log",
    tabSettings: "Tetapan",
    openSummary: "{0} terbuka · paling lama menunggu {1}",
    noOpenSummary: "Tiada kes terbuka",
    ageDay: "h",
    ageHour: "j",
    ageMinute: "m",
    ageNow: "<1m",
    filterActive: "Terbuka",
    filterHidden: "Tersembunyi",
    filterResolved: "Selesai",
    filterAll: "Semua",
    allTypes: "Semua jenis",
    allCategories: "Semua kategori",
    priorityUrgent: "Segera",
    priorityHigh: "Tinggi",
    statusOpen: "Terbuka",
    statusHidden: "Tersembunyi — menunggu semakan",
    statusActioned: "Diambil tindakan",
    statusDismissed: "Ditolak",
    statusClosed: "Ditutup",
    decisionDismissed: "Tiada pelanggaran",
    decisionRestored: "Dipulihkan",
    decisionRemoved: "Dibuang",
    decisionWarned: "Diberi amaran",
    decisionTargetDeleted: "Dipadam oleh penulis",
    reportsCount: "{0} laporan · {1} dikira",
    firstReported: "Mula dilaporkan {0}",
    anonymousAuthor: "Penulis tanpa nama",
    strikesCount: "{0} amaran terkini",
    autoHidden: "Disembunyi automatik",
    actionDismiss: "Tolak",
    actionRestore: "Pulihkan",
    actionRemove: "Buang",
    actionWarn: "Beri amaran",
    actionRestrict: "Sekat",
    actionUnmask: "Dedahkan penulis",
    reasonLabel: "Sebab (wajib)",
    reasonHelp: "Disimpan dalam log. Pembuangan dan amaran menunjukkannya kepada penulis.",
    reasonTooShort: "Sila berikan sebab.",
    dismissTitle: "Tolak laporan ini?",
    dismissBody: "Tiada peraturan dilanggar. Pelapor dimaklumkan ia telah disemak.",
    restoreTitle: "Pulihkan {0} ini?",
    restoreBody: "Ia kelihatan semula, penulis dimaklumkan, dan pelapor diberitahu ia telah disemak.",
    removeTitle: "Buang {0} ini?",
    removeBody: "Ia kekal tersembunyi. Penulis menerima sebab anda dan satu amaran. Tindakan ini tidak boleh dibuat asal, tetapi penulis boleh merayu.",
    warnTitle: "Beri amaran kepada penulis?",
    warnBody: "Penulis menerima sebab anda dan satu amaran. Tindakan ini tidak boleh dibuat asal, tetapi penulis boleh merayu.",
    doneDismissed: "Laporan ditolak",
    doneRestored: "Dipulihkan",
    doneRemoved: "Dibuang — penulis dimaklumkan",
    doneWarned: "Amaran diberi",
    doneRestricted: "Sekatan dikenakan — pengguna dimaklumkan",
    undone: "Dibuat asal",
    restrictTitle: "Sekat pengguna",
    restrictWhat: "Apa yang mereka tidak boleh buat?",
    restrictFor: "Berapa lama?",
    durationDay: "1 hari",
    durationDays: "{0} hari",
    durationPermanent: "Kekal",
    severeWarning: "Sekatan kekal dan sekatan seluruh akaun adalah serius. Pastikan ini betul.",
    pickScope: "Pilih sekurang-kurangnya satu.",
    unmaskTitle: "Dedahkan penulis tanpa nama?",
    unmaskBody: "Hanya atas sebab keselamatan atau undang-undang. Sebab anda dilog dan boleh dibaca oleh semua admin.",
    unmaskReasonHelp: "Sekurang-kurangnya 10 aksara.",
    unmaskResult: "Penulis: {0} (@{1})",
    unmaskNone: "Akaun penulis tiada lagi.",
    bulkSelected: "{0} dipilih",
    bulkDismiss: "Tolak yang dipilih",
    bulkRemove: "Buang yang dipilih",
    bulkHint: "Tindakan pukal hanya untuk spam.",
    bulkDone: "{0} kes diselesaikan",
    noOpenCases: "Tiada kes terbuka",
    noOpenCasesBody: "Tiada apa-apa yang menunggu semakan.",
    noCasesFilter: "Tiada kes sepadan dengan penapis ini.",
    noClubRequests: "Tiada permohonan kelab",
    approve: "Lulus",
    reject: "Tolak",
    approveTitle: "Luluskan {0} sebagai kelab?",
    approveBody: "Mereka menjadi kelab disahkan dan boleh menyemat pengumuman.",
    rejectClubTitle: "Tolak permohonan kelab ini?",
    clubApproved: "Kelab diluluskan — mereka telah dimaklumkan",
    clubRejected: "Permohonan ditolak — mereka telah dimaklumkan",
    noAppeals: "Tiada rayuan menunggu",
    pendingOnly: "Menunggu sahaja",
    accept: "Terima",
    acceptTitle: "Terima rayuan ini?",
    acceptBody: "Keputusan diterbalikkan (kandungan dipulihkan atau sekatan ditarik balik) dan pengguna dimaklumkan.",
    rejectAppealTitle: "Tolak rayuan ini?",
    rejectAppealBody: "Keputusan kekal. Pengguna akan melihat nota anda.",
    noteLabel: "Nota kepada pengguna (wajib)",
    appealAcceptedDone: "Rayuan diterima — pengguna dimaklumkan",
    appealRejectedDone: "Rayuan ditolak — pengguna dimaklumkan",
    appealAbout: "Merayu",
    noRestrictions: "Tiada sekatan aktif",
    activeOnly: "Aktif sahaja",
    lift: "Tarik balik awal",
    liftTitle: "Tarik balik sekatan ini?",
    lifted: "Sekatan ditarik balik — pengguna dimaklumkan",
    automatic: "Automatik",
    untilDate: "Sehingga {0}",
    permanent: "Kekal",
    ended: "Tamat",
    restrictSomeone: "Sekat pengguna",
    usernameLabel: "Nama pengguna",
    userNotFound: "Tiada pengguna dengan nama itu.",
    byName: "Oleh {0}",
    bySystem: "Oleh sistem",
    noLog: "Tiada entri log",
    filterAction: "Tapis mengikut tindakan",
    actorAll: "Semua",
    actorSystem: "Sistem",
    actorAdmin: "Admin",
    actorOwner: "Pemilik",
    actorUser: "Pengguna",
    downloadCsv: "Muat turun CSV",
    csvDownloaded: "CSV dimuat turun",
    csvCopied: "CSV disalin ke papan klip",
    settingsSaved: "Tetapan disimpan",
    settingsNotSaved: "Tidak disimpan — hanya pemilik boleh menukar tetapan ini.",
    sAutoHide: "Bilangan pelapor sebelum disembunyi automatik",
    sPriority: "Disembunyi pada laporan pertama",
    sStrikeWindow: "Tempoh amaran (hari)",
    sStrikes: "Amaran sebelum sekatan automatik",
    sAutoRestrictDays: "Tempoh sekatan automatik (hari)",
    sNewHours: "Tempoh akaun baharu (jam)",
    sNewPosts: "Akaun baharu: siaran sejam",
    sNewComments: "Akaun baharu: komen sejam",
    sNewListings: "Akaun baharu: barang sejam",
    sNewEvents: "Akaun baharu: acara sejam",
    sReporterMin: "Kualiti pelapor: laporan selesai sebelum ia digunakan",
    sReporterRatio: "Abaikan pelapor dengan nisbah ditolak melebihi (0–1)",
    sMaxPins: "Siaran disemat bagi setiap kelab",
    sPinDays: "Tempoh semat (hari)",
    mustBeAtLeast: "Masukkan nombor bulat sekurang-kurangnya {0}",
    mustBeRatio: "Masukkan nombor dari 0 hingga 1",
    errNotAdmin: "Anda tiada akses admin.",
    errAlreadyResolved: "Seseorang sudah menguruskan ini. Senarai telah dimuat semula.",
    errCannotUndo: "Sudah terlambat untuk membuat asal.",
    errProtectedUser: "Hanya pemilik boleh menyekat admin.",
    errSelf: "Anda tidak boleh menyekat diri sendiri.",
    errNotFound: "Item ini tiada lagi.",
    errNoUser: "Penulis tidak dapat dikenal pasti (akaun dipadam).",
    errNotPending: "Permohonan ini sudah diuruskan.",
    errBulkSpamOnly: "Tindakan pukal hanya untuk kes yang dilaporkan sebagai spam sahaja.",
  );

  /// Japanese is being dropped from the app; English stands in.
  static const ja = en;

  String typeLabel(String? type) => switch (type) {
        'post' => typePost,
        'comment' => typeComment,
        'event' => typeEvent,
        'listing' => typeListing,
        _ => typeUser,
      };

  String categoryLabel(String? c) => switch (c) {
        'spam' => catSpam,
        'scam' => catScam,
        'harassment' => catHarassment,
        'inappropriate' => catInappropriate,
        'minor_safety' => catMinorSafety,
        'misinformation' => catMisinformation,
        _ => catOther,
      };

  /// English label stored in `reports.reason` (the DB keeps one language).
  static String categoryReason(String c) => en.categoryLabel(c);

  String scopeLabel(String? scope) => switch (scope) {
        'post' => scopePost,
        'comment' => scopeComment,
        'market' => scopeMarket,
        'events' => scopeEvents,
        _ => scopeAccount,
      };

  String cantTitle(String? scope) => switch (scope) {
        'post' => cantPost,
        'comment' => cantComment,
        'market' => cantSell,
        'events' => cantEvents,
        _ => cantAccount,
      };

  String statusLabel(String? status) => switch (status) {
        'hidden' => statusHidden,
        'actioned' => statusActioned,
        'dismissed' => statusDismissed,
        'closed' => statusClosed,
        _ => statusOpen,
      };

  String decisionLabel(String? d) => switch (d) {
        'dismissed' => decisionDismissed,
        'restored' => decisionRestored,
        'removed' => decisionRemoved,
        'warned' => decisionWarned,
        'target_deleted' => decisionTargetDeleted,
        _ => '',
      };

  String appealStatusLabel(String? s) => switch (s) {
        'accepted' => appealAccepted,
        'rejected' => appealRejected,
        _ => appealPending,
      };

  String rateKind(String? k) => switch (k) {
        'comment' => rateKindComment,
        'listing' => rateKindListing,
        'event' => rateKindEvent,
        _ => rateKindPost,
      };

  String durationLabel(Duration? d) => d == null
      ? durationPermanent
      : d.inDays == 1
          ? durationDay
          : durationDays.fill([d.inDays]);
}

extension ModerationStringsOf on AppStrings {
  /// The [ModerationStrings] matching this language table.
  ModerationStrings get mod {
    if (identical(this, AppStrings.ms)) return ModerationStrings.ms;
    return ModerationStrings.en;
  }
}
