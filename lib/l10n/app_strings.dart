/// Lightweight app localization: English (default), Bahasa Melayu, Japanese.
///
/// Usage: `context.watch<LanguageCubit>().state.strings.navHome`
/// or the shorthand extension `context.l10n.navHome` (see language_cubit.dart).
/// Outside build (callbacks, after an await) use `context.l10nRead`.
///
/// Strings with dynamic parts use `{0}`, `{1}` placeholders, filled with
/// [StringFill.fill]: `s.attendingCount.fill([n])`.
///
/// Terminology (one word per concept, keep it that way):
///   Market (never Marketplace/Shop) · Comments (never Replies/Discussion)
///   Create post · Create event · Sell item · Publish (submit)
///   Ended / Sold (badges are the uppercase form)
enum AppLanguage { en, ms, ja }

extension AppLanguageName on AppLanguage {
  /// Each language in its own script — deliberately not translated.
  String get nativeName => switch (this) {
        AppLanguage.en => "English",
        AppLanguage.ms => "B. Melayu",
        AppLanguage.ja => "日本語",
      };
}

extension StringFill on String {
  /// Replaces `{0}`, `{1}`… with [args].
  String fill(List<Object?> args) {
    var out = this;
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', '${args[i]}');
    }
    return out;
  }
}

class AppStrings {
  /// Brand name — never translated.
  static const appName = "MYKerawang";

  // Navigation
  final String navHome;
  final String navSearch;
  final String navMarket;
  final String navEvents;
  final String navProfile;
  final String createPost;

  // Home
  final String happeningSoon;
  final String freshFinds;
  final String refresh;
  final String notifications;
  final String settings;
  final String connectionError;
  final String tryAgain;

  // Right rail
  final String eventsThisWeek;
  final String pastEvents;
  final String newInMarket;

  // Composer + embeds
  final String composerHint;
  final String viewItem;
  final String viewEvent;

  // Login
  final String welcomeBack;
  final String loginToContinue;
  final String joinApp;
  final String registerToStart;
  final String email;
  final String password;
  final String showPassword;
  final String hidePassword;
  final String login;
  final String signUp;
  final String continueWithGoogle;
  final String newUserPrefix;
  final String createAccount;
  final String haveAccountPrefix;
  final String loginLink;
  final String forgotPassword;
  final String enterEmailFirst;
  final String resetLinkSent;

  // Marketplace
  final String marketplaceTitle;
  final String searchItems;
  final String noItemsFound;

  // Create actions
  final String sellItem;
  final String takePhoto;
  final String chooseFromGallery;
  final String viewFullscreen;
  final String setAsCover;
  final String removePhoto;
  final String createPostTitle;
  final String post;
  final String save;
  final String cancel;
  final String delete;
  final String edit;
  final String share;
  final String report;
  final String searchEvents;
  final String eventsTitle;
  final String profileTitle;
  final String threadTitle;
  final String notificationsTitle;
  final String settingsTitle;
  final String updateAvailable;
  final String updateNow;
  final String checkForUpdates;
  final String upToDate;
  final String noNotifications;
  final String comments;
  final String whatsOnYourMind;
  final String postedAnonymously;
  final String addTags;
  final String tagsHint;
  final String saveChanges;
  final String saved;
  final String saving;
  final String changePhoto;
  final String cropHint;
  final String editProfile;
  final String followers;
  final String following;
  final String follow;
  final String unfollow;

  // Settings
  final String language;


  // Common
  final String errorWithDetail;
  final String close;
  final String back;
  final String next;
  final String finish;
  final String more;
  final String required;
  final String fieldRequired;
  final String invalid;
  final String seeAll;
  final String all;
  final String untitled;
  final String userNotFound;
  final String viewProfile;
  final String repost;
  final String description;
  final String noDetails;
  final String qrCode;
  final String pageNotFound;
  final String contentUnavailable;
  final String goHome;
  final String imageUnavailable;
  final String listEmpty;
  final String loginToSeeNotifications;

  // Content kinds (badges)
  final String kindEvent;
  final String kindPost;
  final String people;
  final String posts;

  // Roles
  final String roleStudent;
  final String roleClub;
  final String roleClubPending;
  final String roleAdmin;
  final String roleOwner;
  final String anonymous;

  // Status
  final String ended;
  final String sold;
  final String markAsSold;
  final String markAvailable;
  final String markedSold;
  final String markedAvailable;

  // Comments
  final String commentCountOne;
  final String commentCountMany;
  final String noComments;
  final String beFirstToComment;
  final String commentHint;
  final String refreshComments;

  // Report
  final String reportUser;
  final String reportTitle;
  final String reportReasonSpam;
  final String reportReasonHate;
  final String reportReasonInappropriate;
  final String reportReasonMisinfo;
  final String reportReasonOther;
  final String reportThanks;
  final String reportFailed;

  // Event detail
  final String cancelEvent;
  final String cancelEventConfirm;
  final String keepEvent;
  final String eventCancelled;
  final String leavingApp;
  final String externalLinkWarning;
  final String openAnyway;

  /// Shown when a stored link is not a scheme the app will launch
  /// (`javascript:`, `data:`, `intent:` …).
  final String linkUnsupported;
  final String locationTba;
  final String dateTba;
  final String attendingCount;
  final String join;
  final String joined;
  final String loginToJoin;
  final String organizer;
  final String aboutEvent;
  final String registrationClosed;
  final String registerOnline;
  final String askAboutEvent;
  final String noEventsFound;

  // Item detail
  final String deleteListing;
  final String deleteListingConfirm;
  final String deletePermanently;
  final String listingDeleted;
  final String contactSeller;
  final String contactOrBuy;
  final String buyingFrom;
  final String seller;
  final String downloadQr;
  final String saveToGallery;
  final String scanToPay;
  final String chatOnWhatsApp;
  final String sellerNoPhone;
  final String whatsAppInterest;
  final String categoryGeneral;
  final String priceLine;

  // Share
  final String invalidPhone;
  final String whatsAppFailed;
  final String shareFooter;
  final String message;
  final String photosCount;
  final String captionDropWarning;
  final String textCopied;
  final String copyText;

  // Settings
  final String theme;
  final String taglineKampus;
  final String taglineIstana;
  final String taglineNoir;
  final String eventAlerts;
  final String newEventsSetting;
  final String newEventsSettingSub;
  final String reminders;
  final String remindersSub;
  final String fixNotifPermissions;
  final String openSystemSettings;
  final String priceDrops;
  final String priceDropsSub;
  final String signOut;
  final String versionLabel;
  final String versionBuildLabel;

  // Profile + edit profile
  final String myCode;
  final String scan;
  final String cameraError;
  final String activity;
  final String noPostsYet;
  final String noEventsYet;
  final String nothingForSale;
  final String username;
  final String usernameRequired;
  final String usernameMin;
  final String usernameChars;
  final String usernameTaken;
  final String usernameTakenShort;
  final String usernameHelper;
  final String displayName;
  final String displayNameHelper;
  final String bio;
  final String contactDetails;
  final String phoneNumber;
  final String phoneHint;
  final String phoneInvalid;
  final String phoneRequired;
  final String website;
  final String duitnowForSelling;
  final String duitnowHelp;
  final String tapToUploadQr;
  final String changeQr;
  final String profileUpdated;
  final String discardChangesTitle;
  final String unsavedChanges;
  final String keepEditing;
  final String discard;

  // Onboarding
  final String welcomeTitle;
  final String setupTitle;
  final String setupSubtitle;
  final String contactSubtitle;
  final String whatsappNumber;
  final String whatsappHelper;
  final String registeringClub;
  final String registeringClubSub;
  final String clubReference;
  final String clubReferenceHelper;
  final String clubDetailsNeeded;
  final String fixErrorsFirst;

  // Login errors
  final String fillAllFields;
  final String checkEmailConfirm;
  final String genericAuthError;
  final String googleSignInFailed;

  // Create post / event / listing
  final String createEvent;
  final String editEvent;
  final String editListing;
  final String publish;
  final String titleRequired;
  final String postedSuccess;
  final String referencingEvent;
  final String referencingItem;
  final String postTitleHint;
  final String postAnonymously;
  final String postAnonymouslySub;
  final String addPhotoRequired;
  final String listingUpdated;
  final String listingPublished;
  final String photos;
  final String addPhotos;
  final String cover;
  final String photoTip;
  final String title;
  final String listingTitleHint;
  final String priceLabel;
  final String category;
  final String eventTitle;
  final String eventTitleHint;
  final String location;
  final String locationHint;
  final String registrationLinkOptional;
  final String eventDescHint;
  final String privacy;
  final String publicEvent;
  final String starts;
  final String ends;
  final String select;
  final String mustBeAfterStart;

  // Search
  final String searchHint;
  final String startTyping;
  final String noResults;
  final String showMore;
  final String postedBy;
  final String replyTo;

  // Notifications written by the client
  final String notifMentionTitle;
  final String notifMentionPostBody;
  final String notifMentionEventTitle;
  final String notifMentionEventBody;
  final String notifMentionCommentTitle;
  final String notifMentionCommentBody;
  final String notifFollowTitle;
  final String notifFollowBody;

  const AppStrings({
    required this.navHome,
    required this.navSearch,
    required this.navMarket,
    required this.navEvents,
    required this.navProfile,
    required this.createPost,
    required this.happeningSoon,
    required this.freshFinds,
    required this.refresh,
    required this.notifications,
    required this.settings,
    required this.connectionError,
    required this.tryAgain,
    required this.eventsThisWeek,
    required this.pastEvents,
    required this.newInMarket,
    required this.composerHint,
    required this.viewItem,
    required this.viewEvent,
    required this.welcomeBack,
    required this.loginToContinue,
    required this.joinApp,
    required this.registerToStart,
    required this.email,
    required this.password,
    required this.showPassword,
    required this.hidePassword,
    required this.login,
    required this.signUp,
    required this.continueWithGoogle,
    required this.newUserPrefix,
    required this.createAccount,
    required this.haveAccountPrefix,
    required this.loginLink,
    required this.forgotPassword,
    required this.enterEmailFirst,
    required this.resetLinkSent,
    required this.marketplaceTitle,
    required this.searchItems,
    required this.noItemsFound,
    required this.sellItem,
    required this.takePhoto,
    required this.chooseFromGallery,
    required this.viewFullscreen,
    required this.setAsCover,
    required this.removePhoto,
    required this.createPostTitle,
    required this.post,
    required this.save,
    required this.cancel,
    required this.delete,
    required this.edit,
    required this.share,
    required this.report,
    required this.searchEvents,
    required this.eventsTitle,
    required this.profileTitle,
    required this.threadTitle,
    required this.notificationsTitle,
    required this.settingsTitle,
    required this.updateAvailable,
    required this.updateNow,
    required this.checkForUpdates,
    required this.upToDate,
    required this.noNotifications,
    required this.comments,
    required this.whatsOnYourMind,
    required this.postedAnonymously,
    required this.addTags,
    required this.tagsHint,
    required this.saveChanges,
    required this.saved,
    required this.saving,
    required this.changePhoto,
    required this.cropHint,
    required this.editProfile,
    required this.followers,
    required this.following,
    required this.follow,
    required this.unfollow,
    required this.language,
    required this.errorWithDetail,
    required this.close,
    required this.back,
    required this.next,
    required this.finish,
    required this.more,
    required this.required,
    required this.fieldRequired,
    required this.invalid,
    required this.seeAll,
    required this.all,
    required this.untitled,
    required this.userNotFound,
    required this.viewProfile,
    required this.repost,
    required this.description,
    required this.noDetails,
    required this.qrCode,
    required this.pageNotFound,
    required this.contentUnavailable,
    required this.goHome,
    required this.imageUnavailable,
    required this.listEmpty,
    required this.loginToSeeNotifications,
    required this.kindEvent,
    required this.kindPost,
    required this.people,
    required this.posts,
    required this.roleStudent,
    required this.roleClub,
    required this.roleClubPending,
    required this.roleAdmin,
    required this.roleOwner,
    required this.anonymous,
    required this.ended,
    required this.sold,
    required this.markAsSold,
    required this.markAvailable,
    required this.markedSold,
    required this.markedAvailable,
    required this.commentCountOne,
    required this.commentCountMany,
    required this.noComments,
    required this.beFirstToComment,
    required this.commentHint,
    required this.refreshComments,
    required this.reportUser,
    required this.reportTitle,
    required this.reportReasonSpam,
    required this.reportReasonHate,
    required this.reportReasonInappropriate,
    required this.reportReasonMisinfo,
    required this.reportReasonOther,
    required this.reportThanks,
    required this.reportFailed,
    required this.cancelEvent,
    required this.cancelEventConfirm,
    required this.keepEvent,
    required this.eventCancelled,
    required this.leavingApp,
    required this.externalLinkWarning,
    required this.openAnyway,
    required this.linkUnsupported,
    required this.locationTba,
    required this.dateTba,
    required this.attendingCount,
    required this.join,
    required this.joined,
    required this.loginToJoin,
    required this.organizer,
    required this.aboutEvent,
    required this.registrationClosed,
    required this.registerOnline,
    required this.askAboutEvent,
    required this.noEventsFound,
    required this.deleteListing,
    required this.deleteListingConfirm,
    required this.deletePermanently,
    required this.listingDeleted,
    required this.contactSeller,
    required this.contactOrBuy,
    required this.buyingFrom,
    required this.seller,
    required this.downloadQr,
    required this.saveToGallery,
    required this.scanToPay,
    required this.chatOnWhatsApp,
    required this.sellerNoPhone,
    required this.whatsAppInterest,
    required this.categoryGeneral,
    required this.priceLine,
    required this.invalidPhone,
    required this.whatsAppFailed,
    required this.shareFooter,
    required this.message,
    required this.photosCount,
    required this.captionDropWarning,
    required this.textCopied,
    required this.copyText,
    required this.theme,
    required this.taglineKampus,
    required this.taglineIstana,
    required this.taglineNoir,
    required this.eventAlerts,
    required this.newEventsSetting,
    required this.newEventsSettingSub,
    required this.reminders,
    required this.remindersSub,
    required this.fixNotifPermissions,
    required this.openSystemSettings,
    required this.priceDrops,
    required this.priceDropsSub,
    required this.signOut,
    required this.versionLabel,
    required this.versionBuildLabel,
    required this.myCode,
    required this.scan,
    required this.cameraError,
    required this.activity,
    required this.noPostsYet,
    required this.noEventsYet,
    required this.nothingForSale,
    required this.username,
    required this.usernameRequired,
    required this.usernameMin,
    required this.usernameChars,
    required this.usernameTaken,
    required this.usernameTakenShort,
    required this.usernameHelper,
    required this.displayName,
    required this.displayNameHelper,
    required this.bio,
    required this.contactDetails,
    required this.phoneNumber,
    required this.phoneHint,
    required this.phoneInvalid,
    required this.phoneRequired,
    required this.website,
    required this.duitnowForSelling,
    required this.duitnowHelp,
    required this.tapToUploadQr,
    required this.changeQr,
    required this.profileUpdated,
    required this.discardChangesTitle,
    required this.unsavedChanges,
    required this.keepEditing,
    required this.discard,
    required this.welcomeTitle,
    required this.setupTitle,
    required this.setupSubtitle,
    required this.contactSubtitle,
    required this.whatsappNumber,
    required this.whatsappHelper,
    required this.registeringClub,
    required this.registeringClubSub,
    required this.clubReference,
    required this.clubReferenceHelper,
    required this.clubDetailsNeeded,
    required this.fixErrorsFirst,
    required this.fillAllFields,
    required this.checkEmailConfirm,
    required this.genericAuthError,
    required this.googleSignInFailed,
    required this.createEvent,
    required this.editEvent,
    required this.editListing,
    required this.publish,
    required this.titleRequired,
    required this.postedSuccess,
    required this.referencingEvent,
    required this.referencingItem,
    required this.postTitleHint,
    required this.postAnonymously,
    required this.postAnonymouslySub,
    required this.addPhotoRequired,
    required this.listingUpdated,
    required this.listingPublished,
    required this.photos,
    required this.addPhotos,
    required this.cover,
    required this.photoTip,
    required this.title,
    required this.listingTitleHint,
    required this.priceLabel,
    required this.category,
    required this.eventTitle,
    required this.eventTitleHint,
    required this.location,
    required this.locationHint,
    required this.registrationLinkOptional,
    required this.eventDescHint,
    required this.privacy,
    required this.publicEvent,
    required this.starts,
    required this.ends,
    required this.select,
    required this.mustBeAfterStart,
    required this.searchHint,
    required this.startTyping,
    required this.noResults,
    required this.showMore,
    required this.postedBy,
    required this.replyTo,
    required this.notifMentionTitle,
    required this.notifMentionPostBody,
    required this.notifMentionEventTitle,
    required this.notifMentionEventBody,
    required this.notifMentionCommentTitle,
    required this.notifMentionCommentBody,
    required this.notifFollowTitle,
    required this.notifFollowBody,
  });

  static const en = AppStrings(
    navHome: "Home",
    navSearch: "Search",
    navMarket: "Market",
    navEvents: "Events",
    navProfile: "Profile",
    createPost: "Create post",
    happeningSoon: "Happening Soon",
    freshFinds: "Fresh Finds",
    refresh: "Refresh",
    notifications: "Notifications",
    settings: "Settings",
    connectionError: "Couldn't connect. Try again?",
    tryAgain: "Try again",
    eventsThisWeek: "Events this week",
    pastEvents: "Past events",
    newInMarket: "Fresh in the market",
    composerHint: "What's happening at kolej?",
    viewItem: "View item",
    viewEvent: "View event",
    welcomeBack: "Welcome back",
    loginToContinue: "Login to continue",
    joinApp: "Join MYKerawang",
    registerToStart: "Create an account to get started",
    email: "Email",
    password: "Password",
    showPassword: "Show",
    hidePassword: "Hide",
    login: "Login",
    signUp: "Sign up",
    continueWithGoogle: "Continue with Google",
    newUserPrefix: "New user? ",
    createAccount: "Create account",
    haveAccountPrefix: "Have an account? ",
    loginLink: "Login",
    forgotPassword: "Forgot password?",
    enterEmailFirst: "Enter your email first",
    resetLinkSent: "Password reset link sent — check your email",
    marketplaceTitle: "Market",
    searchItems: "Search items...",
    noItemsFound: "No items found",
    sellItem: "Sell item",
    takePhoto: "Take photo",
    chooseFromGallery: "Choose from gallery",
    viewFullscreen: "View fullscreen",
    setAsCover: "Set as cover photo",
    removePhoto: "Remove photo",
    createPostTitle: "Create post",
    post: "POST",
    save: "SAVE",
    cancel: "Cancel",
    delete: "Delete",
    edit: "Edit",
    share: "Share",
    report: "Report",
    searchEvents: "Search events...",
    eventsTitle: "Events",
    profileTitle: "Profile",
    threadTitle: "Thread",
    notificationsTitle: "Notifications",
    settingsTitle: "Settings",
    updateAvailable: "A new version of MYKerawang is available",
    updateNow: "Update",
    checkForUpdates: "Check for updates",
    upToDate: "You're on the latest version",
    noNotifications: "No new notifications",
    comments: "Comments",
    whatsOnYourMind: "What's on your mind?",
    postedAnonymously: "Posted anonymously",
    addTags: "Tags",
    tagsHint: "#studygroup #kolej ...",
    saveChanges: "Save changes",
    saved: "Saved",
    saving: "Saving...",
    changePhoto: "Change photo",
    cropHint: "Drag and pinch to position",
    editProfile: "Edit profile",
    followers: "Followers",
    following: "Following",
    follow: "Follow",
    unfollow: "Unfollow",
    language: "Language",
    errorWithDetail: "Error: {0}",
    close: "Close",
    back: "Back",
    next: "Next",
    finish: "Finish",
    more: "More",
    required: "Required",
    fieldRequired: "{0} is required",
    invalid: "Invalid",
    seeAll: "See all",
    all: "All",
    untitled: "Untitled",
    userNotFound: "User not found",
    viewProfile: "View profile",
    repost: "Repost",
    description: "Description",
    noDetails: "No details provided.",
    qrCode: "QR code",
    pageNotFound: "Page not found",
    contentUnavailable: "This content is no longer available",
    goHome: "Go home",
    imageUnavailable: "Image unavailable",
    listEmpty: "Nobody here yet",
    loginToSeeNotifications: "Log in to see notifications",
    kindEvent: "Event",
    kindPost: "Post",
    people: "People",
    posts: "Posts",
    roleStudent: "Student",
    roleClub: "Official club",
    roleClubPending: "Club (pending approval)",
    roleAdmin: "Admin",
    roleOwner: "Owner",
    anonymous: "Anonymous",
    ended: "Ended",
    sold: "Sold",
    markAsSold: "Mark as sold",
    markAvailable: "Mark as available",
    markedSold: "Marked as sold",
    markedAvailable: "Marked as available",
    commentCountOne: "{0} comment",
    commentCountMany: "{0} comments",
    noComments: "No comments yet",
    beFirstToComment: "Be the first to comment!",
    commentHint: "Write a comment...",
    refreshComments: "Refresh comments",
    reportUser: "Report user",
    reportTitle: "Report content",
    reportReasonSpam: "Spam or scam",
    reportReasonHate: "Hate speech or harassment",
    reportReasonInappropriate: "Inappropriate content",
    reportReasonMisinfo: "Misinformation",
    reportReasonOther: "Other",
    reportThanks: "Thanks for reporting. We'll review this.",
    reportFailed: "Couldn't submit report.",
    cancelEvent: "Cancel event",
    cancelEventConfirm: "Are you sure? This can't be undone.",
    keepEvent: "Keep event",
    eventCancelled: "Event cancelled",
    leavingApp: "Leaving MYKerawang",
    externalLinkWarning: "This link goes to an external site:\n\n{0}\n\nAre you sure it's safe?",
    openAnyway: "Open anyway",
    linkUnsupported: "That link cannot be opened.",
    locationTba: "TBA",
    dateTba: "Date TBA",
    attendingCount: "{0} attending",
    join: "Join",
    joined: "Joined",
    loginToJoin: "Log in to join this event",
    organizer: "Organizer",
    aboutEvent: "About event",
    registrationClosed: "Registration closed",
    registerOnline: "Register online",
    askAboutEvent: "Ask about this event...",
    noEventsFound: "No events found",
    deleteListing: "Delete listing",
    deleteListingConfirm: "Delete this listing permanently?",
    deletePermanently: "Delete permanently",
    listingDeleted: "Listing deleted",
    contactSeller: "Contact seller",
    contactOrBuy: "Contact / Buy",
    buyingFrom: "Buying from @{0}",
    seller: "Seller",
    downloadQr: "Download QR",
    saveToGallery: "Save to gallery",
    scanToPay: "Screenshot & scan to pay",
    chatOnWhatsApp: "Chat on WhatsApp",
    sellerNoPhone: "This seller hasn't added a phone number yet",
    whatsAppInterest: "Hi! I'm interested in your listing \"{0}\" ({1}) on MYKerawang.",
    categoryGeneral: "General",
    priceLine: "Price: {0}",
    invalidPhone: "Seller's phone number looks invalid: \"{0}\"",
    whatsAppFailed: "Couldn't open WhatsApp. Is it installed?",
    shareFooter: "Check this out on MYKerawang!",
    message: "Message",
    photosCount: "Photos ({0}/{1})",
    captionDropWarning: "Some apps drop the caption when sharing multiple photos",
    textCopied: "Text copied",
    copyText: "Copy text",
    theme: "Theme",
    taglineKampus: "Loud & young",
    taglineIstana: "Crafted & warm",
    taglineNoir: "Premium & dark",
    eventAlerts: "Event alerts",
    newEventsSetting: "New events",
    newEventsSettingSub: "Get notified when new events are posted",
    reminders: "Reminders",
    remindersSub: "1 hour before events you joined",
    fixNotifPermissions: "Fix notification permissions",
    openSystemSettings: "Open system settings to enable",
    priceDrops: "Price drops",
    priceDropsSub: "Notify when saved items drop in price",
    signOut: "Sign out",
    versionLabel: "Version {0}",
    versionBuildLabel: "Version {0} · build {1}",
    myCode: "My code",
    scan: "Scan",
    cameraError: "Camera error: {0}",
    activity: "Activity",
    noPostsYet: "No posts yet",
    noEventsYet: "No events yet",
    nothingForSale: "Nothing for sale yet",
    username: "Username",
    usernameRequired: "Username is required",
    usernameMin: "At least 3 characters",
    usernameChars: "Only letters, numbers and _",
    usernameTaken: "Username @{0} is already taken",
    usernameTakenShort: "Username already taken",
    usernameHelper: "Unique ID (e.g. fahmi_99)",
    displayName: "Display name",
    displayNameHelper: "Your real name or club name",
    bio: "Bio",
    contactDetails: "Contact details",
    phoneNumber: "Phone number",
    phoneHint: "e.g. 0123456789",
    phoneInvalid: "Please enter a valid number",
    phoneRequired: "Phone number is required",
    website: "Website / link",
    duitnowForSelling: "DuitNow QR (for selling)",
    duitnowHelp: "Buyers scan this to pay you",
    tapToUploadQr: "Tap to upload QR",
    changeQr: "Change QR",
    profileUpdated: "Profile updated",
    discardChangesTitle: "Discard changes?",
    unsavedChanges: "You have unsaved changes on this page.",
    keepEditing: "Keep editing",
    discard: "Discard",
    welcomeTitle: "Welcome!",
    setupTitle: "Let's get you set up.",
    setupSubtitle: "Create a unique ID so friends can find you.",
    contactSubtitle: "How should people contact you about events or items?",
    whatsappNumber: "WhatsApp number",
    whatsappHelper: "Required for Market & Events",
    registeringClub: "I'm registering a club",
    registeringClubSub: "Switch to a club account (requires approval)",
    clubReference: "Club ID / reference",
    clubReferenceHelper: "Provide an ID for admin verification",
    clubDetailsNeeded: "Please provide club details/ID for verification.",
    fixErrorsFirst: "Please fix the errors first.",
    fillAllFields: "Please fill in all fields",
    checkEmailConfirm: "Check your email for the confirmation link.",
    genericAuthError: "Something went wrong. Check your connection.",
    googleSignInFailed: "Google sign-in failed: {0}",
    createEvent: "Create event",
    editEvent: "Edit event",
    editListing: "Edit listing",
    publish: "Publish",
    titleRequired: "Please enter a title",
    postedSuccess: "Posted!",
    referencingEvent: "Referencing event:",
    referencingItem: "Referencing item:",
    postTitleHint: "Title (e.g. Lost wallet)",
    postAnonymously: "Post anonymously",
    postAnonymouslySub: "Hide your name from everyone",
    addPhotoRequired: "Please add at least 1 photo.",
    listingUpdated: "Listing updated",
    listingPublished: "Listing published",
    photos: "Photos",
    addPhotos: "Add photos",
    cover: "Cover",
    photoTip: "Tip: tap a photo to set it as cover or view it.",
    title: "Title",
    listingTitleHint: "e.g. Pre-loved textbook",
    priceLabel: "Price (RM)",
    category: "Category",
    eventTitle: "Event title",
    eventTitleHint: "Enter a catchy title",
    location: "Location",
    locationHint: "e.g. Dewan Aspirasi",
    registrationLinkOptional: "Registration link (optional)",
    eventDescHint: "Event details... (use @ to tag speakers/organisers)",
    privacy: "Privacy",
    publicEvent: "Public event",
    starts: "Starts",
    ends: "Ends",
    select: "Select",
    mustBeAfterStart: "Must be after start",
    searchHint: "Search posts, people, items...",
    startTyping: "Start typing to search",
    noResults: "No results found",
    showMore: "Show more results",
    postedBy: "Posted by {0}",
    replyTo: "Re: {0}",
    notifMentionTitle: "You were mentioned",
    notifMentionPostBody: "mentioned you in a post",
    notifMentionEventTitle: "Tagged in an event",
    notifMentionEventBody: "mentioned you in an event description",
    notifMentionCommentTitle: "You were mentioned in a comment",
    notifMentionCommentBody: "replied: {0}",
    notifFollowTitle: "New follower",
    notifFollowBody: "{0} started following you.",
  );

  static const ms = AppStrings(
    navHome: "Utama",
    navSearch: "Cari",
    navMarket: "Pasar",
    navEvents: "Acara",
    navProfile: "Profil",
    createPost: "Jom post",
    happeningSoon: "Jangan Terlepas",
    freshFinds: "Baru Masuk",
    refresh: "Muat semula",
    notifications: "Notifikasi",
    settings: "Tetapan",
    connectionError: "Tak dapat sambung. Cuba lagi?",
    tryAgain: "Cuba semula",
    eventsThisWeek: "Acara minggu ini",
    pastEvents: "Acara lepas",
    newInMarket: "Baru masuk pasar",
    composerHint: "Apa cerita kat kolej?",
    viewItem: "Lihat barang",
    viewEvent: "Jom join",
    welcomeBack: "Selamat kembali",
    loginToContinue: "Log masuk untuk teruskan",
    joinApp: "Jom sertai MYKerawang",
    registerToStart: "Daftar akaun untuk mula",
    email: "Emel",
    password: "Kata laluan",
    showPassword: "Tunjuk",
    hidePassword: "Sembunyi",
    login: "Log masuk",
    signUp: "Daftar",
    continueWithGoogle: "Teruskan dengan Google",
    newUserPrefix: "Pengguna baru? ",
    createAccount: "Daftar sini",
    haveAccountPrefix: "Dah ada akaun? ",
    loginLink: "Log masuk",
    forgotPassword: "Lupa kata laluan?",
    enterEmailFirst: "Masukkan emel dulu",
    resetLinkSent: "Pautan set semula dihantar — semak emel anda",
    marketplaceTitle: "Pasar",
    searchItems: "Cari barang...",
    noItemsFound: "Tiada barang dijumpai",
    sellItem: "Jual barang",
    takePhoto: "Ambil gambar",
    chooseFromGallery: "Pilih dari galeri",
    viewFullscreen: "Lihat skrin penuh",
    setAsCover: "Jadikan gambar utama",
    removePhoto: "Buang gambar",
    createPostTitle: "Buat post",
    post: "HANTAR",
    save: "SIMPAN",
    cancel: "Batal",
    delete: "Padam",
    edit: "Edit",
    share: "Kongsi",
    report: "Lapor",
    searchEvents: "Cari acara...",
    eventsTitle: "Acara",
    profileTitle: "Profil",
    threadTitle: "Bicara",
    notificationsTitle: "Notifikasi",
    settingsTitle: "Tetapan",
    updateAvailable: "Versi baharu MYKerawang tersedia",
    updateNow: "Kemas kini",
    checkForUpdates: "Semak kemas kini",
    upToDate: "Anda menggunakan versi terkini",
    noNotifications: "Tiada notifikasi baru",
    comments: "Komen",
    whatsOnYourMind: "Apa dalam fikiran anda?",
    postedAnonymously: "Dihantar tanpa nama",
    addTags: "Tag",
    tagsHint: "#studygroup #kolej ...",
    saveChanges: "Simpan perubahan",
    saved: "Disimpan",
    saving: "Menyimpan...",
    changePhoto: "Tukar gambar",
    cropHint: "Seret dan cubit untuk laraskan",
    editProfile: "Edit profil",
    followers: "Pengikut",
    following: "Mengikuti",
    follow: "Ikut",
    unfollow: "Berhenti ikut",
    language: "Bahasa",
    errorWithDetail: "Ralat: {0}",
    close: "Tutup",
    back: "Kembali",
    next: "Seterusnya",
    finish: "Selesai",
    more: "Lagi",
    required: "Wajib",
    fieldRequired: "{0} wajib diisi",
    invalid: "Tak sah",
    seeAll: "Lihat semua",
    all: "Semua",
    untitled: "Tanpa tajuk",
    userNotFound: "Pengguna tak dijumpai",
    viewProfile: "Lihat profil",
    repost: "Kongsi semula",
    description: "Penerangan",
    noDetails: "Tiada butiran.",
    qrCode: "Kod QR",
    pageNotFound: "Halaman tak dijumpai",
    contentUnavailable: "Kandungan ni dah tiada",
    goHome: "Ke laman utama",
    imageUnavailable: "Gambar tiada",
    listEmpty: "Belum ada sesiapa",
    loginToSeeNotifications: "Log masuk untuk lihat notifikasi",
    kindEvent: "Acara",
    kindPost: "Post",
    people: "Orang",
    posts: "Post",
    roleStudent: "Pelajar",
    roleClub: "Kelab rasmi",
    roleClubPending: "Kelab (menunggu kelulusan)",
    roleAdmin: "Admin",
    roleOwner: "Pemilik",
    anonymous: "Tanpa nama",
    ended: "Tamat",
    sold: "Terjual",
    markAsSold: "Tanda dah terjual",
    markAvailable: "Tanda masih ada",
    markedSold: "Ditanda terjual",
    markedAvailable: "Ditanda masih ada",
    commentCountOne: "{0} komen",
    commentCountMany: "{0} komen",
    noComments: "Belum ada komen",
    beFirstToComment: "Jadi yang pertama komen!",
    commentHint: "Tulis komen...",
    refreshComments: "Muat semula komen",
    reportUser: "Lapor pengguna",
    reportTitle: "Lapor kandungan",
    reportReasonSpam: "Spam atau scam",
    reportReasonHate: "Ucapan benci atau gangguan",
    reportReasonInappropriate: "Kandungan tak sesuai",
    reportReasonMisinfo: "Maklumat palsu",
    reportReasonOther: "Lain-lain",
    reportThanks: "Terima kasih kerana melapor. Kami akan semak.",
    reportFailed: "Tak dapat hantar laporan.",
    cancelEvent: "Batal acara",
    cancelEventConfirm: "Pasti? Tindakan ni tak boleh diundur.",
    keepEvent: "Kekalkan",
    eventCancelled: "Acara dibatalkan",
    leavingApp: "Keluar dari MYKerawang",
    externalLinkWarning: "Pautan ni ke laman luar:\n\n{0}\n\nPasti ia selamat?",
    openAnyway: "Buka juga",
    linkUnsupported: "Pautan itu tidak boleh dibuka.",
    locationTba: "Belum ditetapkan",
    dateTba: "Tarikh belum ditetapkan",
    attendingCount: "{0} join",
    join: "Join",
    joined: "Dah join",
    loginToJoin: "Log masuk untuk join",
    organizer: "Penganjur",
    aboutEvent: "Tentang acara",
    registrationClosed: "Pendaftaran ditutup",
    registerOnline: "Daftar online",
    askAboutEvent: "Tanya pasal acara ni...",
    noEventsFound: "Tiada acara dijumpai",
    deleteListing: "Padam iklan",
    deleteListingConfirm: "Padam iklan ni secara kekal?",
    deletePermanently: "Padam terus",
    listingDeleted: "Iklan dipadam",
    contactSeller: "Hubungi penjual",
    contactOrBuy: "Hubungi / Beli",
    buyingFrom: "Beli dari @{0}",
    seller: "Penjual",
    downloadQr: "Muat turun QR",
    saveToGallery: "Simpan ke galeri",
    scanToPay: "Screenshot & scan untuk bayar",
    chatOnWhatsApp: "Chat di WhatsApp",
    sellerNoPhone: "Penjual ni belum letak nombor telefon",
    whatsAppInterest: "Hi! Saya berminat dengan iklan \"{0}\" ({1}) di MYKerawang.",
    categoryGeneral: "Umum",
    priceLine: "Harga: {0}",
    invalidPhone: "Nombor telefon penjual tak sah: \"{0}\"",
    whatsAppFailed: "Tak dapat buka WhatsApp. Dah install?",
    shareFooter: "Tengok ni kat MYKerawang!",
    message: "Mesej",
    photosCount: "Gambar ({0}/{1})",
    captionDropWarning: "Sesetengah app buang kapsyen bila kongsi banyak gambar",
    textCopied: "Teks disalin",
    copyText: "Salin teks",
    theme: "Tema",
    taglineKampus: "Bising & muda",
    taglineIstana: "Halus & mesra",
    taglineNoir: "Mewah & gelap",
    eventAlerts: "Notifikasi acara",
    newEventsSetting: "Acara baru",
    newEventsSettingSub: "Dapat notifikasi bila ada acara baru",
    reminders: "Peringatan",
    remindersSub: "1 jam sebelum acara yang anda join",
    fixNotifPermissions: "Betulkan kebenaran notifikasi",
    openSystemSettings: "Buka tetapan sistem untuk aktifkan",
    priceDrops: "Harga turun",
    priceDropsSub: "Notifikasi bila barang disimpan turun harga",
    signOut: "Log keluar",
    versionLabel: "Versi {0}",
    versionBuildLabel: "Versi {0} · binaan {1}",
    myCode: "Kod saya",
    scan: "Imbas",
    cameraError: "Ralat kamera: {0}",
    activity: "Aktiviti",
    noPostsYet: "Belum ada post",
    noEventsYet: "Belum ada acara",
    nothingForSale: "Belum jual apa-apa",
    username: "Username",
    usernameRequired: "Username wajib",
    usernameMin: "Sekurang-kurangnya 3 aksara",
    usernameChars: "Huruf, nombor dan _ sahaja",
    usernameTaken: "Username @{0} dah diambil",
    usernameTakenShort: "Username dah diambil",
    usernameHelper: "ID unik (cth. fahmi_99)",
    displayName: "Nama paparan",
    displayNameHelper: "Nama sebenar atau nama kelab",
    bio: "Bio",
    contactDetails: "Maklumat hubungan",
    phoneNumber: "Nombor telefon",
    phoneHint: "cth. 0123456789",
    phoneInvalid: "Masukkan nombor yang sah",
    phoneRequired: "Nombor telefon wajib",
    website: "Laman web / pautan",
    duitnowForSelling: "DuitNow QR (untuk jualan)",
    duitnowHelp: "Pembeli scan ni untuk bayar anda",
    tapToUploadQr: "Tekan untuk muat naik QR",
    changeQr: "Tukar QR",
    profileUpdated: "Profil dikemas kini",
    discardChangesTitle: "Buang perubahan?",
    unsavedChanges: "Ada perubahan yang belum disimpan.",
    keepEditing: "Terus edit",
    discard: "Buang",
    welcomeTitle: "Selamat datang!",
    setupTitle: "Jom setup akaun.",
    setupSubtitle: "Cipta ID unik supaya kawan boleh cari anda.",
    contactSubtitle: "Macam mana orang nak hubungi anda pasal acara atau barang?",
    whatsappNumber: "Nombor WhatsApp",
    whatsappHelper: "Wajib untuk Pasar & Acara",
    registeringClub: "Saya daftar kelab",
    registeringClubSub: "Tukar ke akaun kelab (perlu kelulusan)",
    clubReference: "ID / rujukan kelab",
    clubReferenceHelper: "Beri ID untuk pengesahan admin",
    clubDetailsNeeded: "Sila beri butiran/ID kelab untuk pengesahan.",
    fixErrorsFirst: "Sila betulkan ralat dulu.",
    fillAllFields: "Sila isi semua ruangan",
    checkEmailConfirm: "Semak emel untuk pautan pengesahan.",
    genericAuthError: "Ada masalah. Semak sambungan.",
    googleSignInFailed: "Log masuk Google gagal: {0}",
    createEvent: "Buat acara",
    editEvent: "Edit acara",
    editListing: "Edit iklan",
    publish: "Terbitkan",
    titleRequired: "Sila masukkan tajuk",
    postedSuccess: "Dah post!",
    referencingEvent: "Merujuk acara:",
    referencingItem: "Merujuk barang:",
    postTitleHint: "Tajuk (cth. Dompet hilang)",
    postAnonymously: "Post tanpa nama",
    postAnonymouslySub: "Sembunyi nama anda daripada semua",
    addPhotoRequired: "Sila tambah sekurang-kurangnya 1 gambar.",
    listingUpdated: "Iklan dikemas kini",
    listingPublished: "Iklan diterbitkan",
    photos: "Gambar",
    addPhotos: "Tambah gambar",
    cover: "Utama",
    photoTip: "Tip: tekan gambar untuk jadikan utama atau lihat.",
    title: "Tajuk",
    listingTitleHint: "cth. Buku teks terpakai",
    priceLabel: "Harga (RM)",
    category: "Kategori",
    eventTitle: "Tajuk acara",
    eventTitleHint: "Masukkan tajuk yang menarik",
    location: "Lokasi",
    locationHint: "cth. Dewan Aspirasi",
    registrationLinkOptional: "Pautan pendaftaran (pilihan)",
    eventDescHint: "Butiran acara... (guna @ untuk tag penceramah/penganjur)",
    privacy: "Privasi",
    publicEvent: "Acara awam",
    starts: "Mula",
    ends: "Tamat",
    select: "Pilih",
    mustBeAfterStart: "Mesti selepas masa mula",
    searchHint: "Cari post, orang, barang...",
    startTyping: "Taip untuk mula cari",
    noResults: "Tiada hasil",
    showMore: "Tunjuk lagi",
    postedBy: "Oleh {0}",
    replyTo: "Re: {0}",
    notifMentionTitle: "Anda disebut",
    notifMentionPostBody: "sebut anda dalam post",
    notifMentionEventTitle: "Ditag dalam acara",
    notifMentionEventBody: "sebut anda dalam penerangan acara",
    notifMentionCommentTitle: "Anda disebut dalam komen",
    notifMentionCommentBody: "membalas: {0}",
    notifFollowTitle: "Pengikut baru",
    notifFollowBody: "{0} mula ikut anda.",
  );

  static const ja = AppStrings(
    navHome: "ホーム",
    navSearch: "検索",
    navMarket: "マーケット",
    navEvents: "イベント",
    navProfile: "プロフィール",
    createPost: "投稿する",
    happeningSoon: "近日開催",
    freshFinds: "新着アイテム",
    refresh: "更新",
    notifications: "通知",
    settings: "設定",
    connectionError: "接続できません。もう一度？",
    tryAgain: "再試行",
    eventsThisWeek: "今週のイベント",
    pastEvents: "過去のイベント",
    newInMarket: "マーケット新着",
    composerHint: "キャンパスで何かあった？",
    viewItem: "商品を見る",
    viewEvent: "参加する",
    welcomeBack: "おかえりなさい",
    loginToContinue: "ログインして続ける",
    joinApp: "MYKerawangへようこそ",
    registerToStart: "アカウントを作成して始めよう",
    email: "メール",
    password: "パスワード",
    showPassword: "表示",
    hidePassword: "非表示",
    login: "ログイン",
    signUp: "登録",
    continueWithGoogle: "Googleで続行",
    newUserPrefix: "初めての方？ ",
    createAccount: "アカウント作成",
    haveAccountPrefix: "アカウントをお持ちの方？ ",
    loginLink: "ログイン",
    forgotPassword: "パスワードをお忘れですか？",
    enterEmailFirst: "先にメールを入力してください",
    resetLinkSent: "再設定リンクを送信しました",
    marketplaceTitle: "マーケット",
    searchItems: "商品を検索...",
    noItemsFound: "商品が見つかりません",
    sellItem: "出品する",
    takePhoto: "写真を撮る",
    chooseFromGallery: "ギャラリーから選択",
    viewFullscreen: "全画面表示",
    setAsCover: "カバーに設定",
    removePhoto: "写真を削除",
    createPostTitle: "投稿を作成",
    post: "投稿",
    save: "保存",
    cancel: "キャンセル",
    delete: "削除",
    edit: "編集",
    share: "共有",
    report: "報告",
    searchEvents: "イベントを検索...",
    eventsTitle: "イベント",
    profileTitle: "プロフィール",
    threadTitle: "スレッド",
    notificationsTitle: "通知",
    settingsTitle: "設定",
    updateAvailable: "MYKerawangの新しいバージョンがあります",
    updateNow: "更新",
    checkForUpdates: "アップデートを確認",
    upToDate: "最新バージョンです",
    noNotifications: "新しい通知はありません",
    comments: "コメント",
    whatsOnYourMind: "いま何してる？",
    postedAnonymously: "匿名で投稿",
    addTags: "タグ",
    tagsHint: "#studygroup #kolej ...",
    saveChanges: "変更を保存",
    saved: "保存しました",
    saving: "保存中...",
    changePhoto: "写真を変更",
    cropHint: "ドラッグ・ピンチで調整",
    editProfile: "プロフィール編集",
    followers: "フォロワー",
    following: "フォロー中",
    follow: "フォロー",
    unfollow: "フォロー解除",
    language: "言語",
    errorWithDetail: "エラー: {0}",
    close: "閉じる",
    back: "戻る",
    next: "次へ",
    finish: "完了",
    more: "その他",
    required: "必須",
    fieldRequired: "{0}は必須です",
    invalid: "無効です",
    seeAll: "すべて見る",
    all: "すべて",
    untitled: "無題",
    userNotFound: "ユーザーが見つかりません",
    viewProfile: "プロフィールを見る",
    repost: "リポスト",
    description: "説明",
    noDetails: "詳細はありません。",
    qrCode: "QRコード",
    pageNotFound: "ページが見つかりません",
    contentUnavailable: "このコンテンツは利用できません",
    goHome: "ホームへ",
    imageUnavailable: "画像を表示できません",
    listEmpty: "まだ誰もいません",
    loginToSeeNotifications: "通知を見るにはログインしてください",
    kindEvent: "イベント",
    kindPost: "投稿",
    people: "人",
    posts: "投稿",
    roleStudent: "学生",
    roleClub: "公式クラブ",
    roleClubPending: "クラブ（承認待ち）",
    roleAdmin: "管理者",
    roleOwner: "オーナー",
    anonymous: "匿名",
    ended: "終了",
    sold: "売り切れ",
    markAsSold: "売り切れにする",
    markAvailable: "販売中に戻す",
    markedSold: "売り切れにしました",
    markedAvailable: "販売中に戻しました",
    commentCountOne: "コメント{0}件",
    commentCountMany: "コメント{0}件",
    noComments: "まだコメントはありません",
    beFirstToComment: "最初のコメントをしよう！",
    commentHint: "コメントを書く...",
    refreshComments: "コメントを更新",
    reportUser: "ユーザーを報告",
    reportTitle: "コンテンツを報告",
    reportReasonSpam: "スパム・詐欺",
    reportReasonHate: "ヘイト・嫌がらせ",
    reportReasonInappropriate: "不適切なコンテンツ",
    reportReasonMisinfo: "誤情報",
    reportReasonOther: "その他",
    reportThanks: "報告ありがとうございます。確認します。",
    reportFailed: "報告を送信できませんでした。",
    cancelEvent: "イベントを中止",
    cancelEventConfirm: "本当によろしいですか？元に戻せません。",
    keepEvent: "残す",
    eventCancelled: "イベントを中止しました",
    leavingApp: "MYKerawangを離れます",
    externalLinkWarning: "外部サイトへのリンクです：\n\n{0}\n\n安全ですか？",
    openAnyway: "それでも開く",
    linkUnsupported: "このリンクは開けません。",
    locationTba: "未定",
    dateTba: "日程未定",
    attendingCount: "{0}人参加",
    join: "参加する",
    joined: "参加中",
    loginToJoin: "参加するにはログインしてください",
    organizer: "主催者",
    aboutEvent: "イベント詳細",
    registrationClosed: "受付終了",
    registerOnline: "オンライン登録",
    askAboutEvent: "このイベントについて質問...",
    noEventsFound: "イベントが見つかりません",
    deleteListing: "出品を削除",
    deleteListingConfirm: "この出品を完全に削除しますか？",
    deletePermanently: "完全に削除",
    listingDeleted: "出品を削除しました",
    contactSeller: "出品者に連絡",
    contactOrBuy: "連絡・購入",
    buyingFrom: "@{0} から購入",
    seller: "出品者",
    downloadQr: "QRをダウンロード",
    saveToGallery: "ギャラリーに保存",
    scanToPay: "スクショしてスキャンで支払い",
    chatOnWhatsApp: "WhatsAppでチャット",
    sellerNoPhone: "出品者はまだ電話番号を登録していません",
    whatsAppInterest: "こんにちは！MYKerawangの出品「{0}」（{1}）に興味があります。",
    categoryGeneral: "一般",
    priceLine: "価格: {0}",
    invalidPhone: "出品者の電話番号が無効です：\"{0}\"",
    whatsAppFailed: "WhatsAppを開けません。インストールされていますか？",
    shareFooter: "MYKerawangでチェック！",
    message: "メッセージ",
    photosCount: "写真 ({0}/{1})",
    captionDropWarning: "複数枚の写真を共有するとキャプションが消えるアプリがあります",
    textCopied: "テキストをコピーしました",
    copyText: "テキストをコピー",
    theme: "テーマ",
    taglineKampus: "元気で若々しく",
    taglineIstana: "丁寧で温かく",
    taglineNoir: "上質でダーク",
    eventAlerts: "イベント通知",
    newEventsSetting: "新しいイベント",
    newEventsSettingSub: "新しいイベントが投稿されたら通知",
    reminders: "リマインダー",
    remindersSub: "参加するイベントの1時間前",
    fixNotifPermissions: "通知の許可を修正",
    openSystemSettings: "システム設定を開いて有効化",
    priceDrops: "値下げ",
    priceDropsSub: "保存した商品が値下げされたら通知",
    signOut: "ログアウト",
    versionLabel: "バージョン {0}",
    versionBuildLabel: "バージョン {0} · ビルド {1}",
    myCode: "マイコード",
    scan: "スキャン",
    cameraError: "カメラエラー: {0}",
    activity: "アクティビティ",
    noPostsYet: "まだ投稿はありません",
    noEventsYet: "まだイベントはありません",
    nothingForSale: "まだ出品はありません",
    username: "ユーザー名",
    usernameRequired: "ユーザー名は必須です",
    usernameMin: "3文字以上",
    usernameChars: "英数字と_のみ",
    usernameTaken: "@{0} は既に使われています",
    usernameTakenShort: "このユーザー名は使われています",
    usernameHelper: "固有ID（例: fahmi_99）",
    displayName: "表示名",
    displayNameHelper: "本名またはクラブ名",
    bio: "自己紹介",
    contactDetails: "連絡先",
    phoneNumber: "電話番号",
    phoneHint: "例: 0123456789",
    phoneInvalid: "有効な番号を入力してください",
    phoneRequired: "電話番号は必須です",
    website: "ウェブサイト・リンク",
    duitnowForSelling: "DuitNow QR（販売用）",
    duitnowHelp: "購入者がこれをスキャンして支払います",
    tapToUploadQr: "タップしてQRをアップロード",
    changeQr: "QRを変更",
    profileUpdated: "プロフィールを更新しました",
    discardChangesTitle: "変更を破棄しますか？",
    unsavedChanges: "保存されていない変更があります。",
    keepEditing: "編集を続ける",
    discard: "破棄",
    welcomeTitle: "ようこそ！",
    setupTitle: "さっそく設定しよう。",
    setupSubtitle: "友達が見つけられるようにIDを作成しよう。",
    contactSubtitle: "イベントや商品について、どう連絡を取りますか？",
    whatsappNumber: "WhatsApp番号",
    whatsappHelper: "マーケットとイベントに必要",
    registeringClub: "クラブとして登録する",
    registeringClubSub: "クラブアカウントに切替（承認が必要）",
    clubReference: "クラブID・参照",
    clubReferenceHelper: "管理者確認用のIDを入力",
    clubDetailsNeeded: "確認のためクラブの詳細・IDを入力してください。",
    fixErrorsFirst: "先にエラーを修正してください。",
    fillAllFields: "すべての項目を入力してください",
    checkEmailConfirm: "確認リンクをメールで確認してください。",
    genericAuthError: "エラーが発生しました。接続を確認してください。",
    googleSignInFailed: "Googleログインに失敗しました: {0}",
    createEvent: "イベント作成",
    editEvent: "イベントを編集",
    editListing: "出品を編集",
    publish: "公開する",
    titleRequired: "タイトルを入力してください",
    postedSuccess: "投稿しました！",
    referencingEvent: "参照イベント:",
    referencingItem: "参照アイテム:",
    postTitleHint: "タイトル（例: 財布をなくした）",
    postAnonymously: "匿名で投稿",
    postAnonymouslySub: "名前を全員に非表示",
    addPhotoRequired: "写真を1枚以上追加してください。",
    listingUpdated: "出品を更新しました",
    listingPublished: "出品しました",
    photos: "写真",
    addPhotos: "写真を追加",
    cover: "カバー",
    photoTip: "ヒント：写真をタップしてカバー設定・表示",
    title: "タイトル",
    listingTitleHint: "例: 中古の教科書",
    priceLabel: "価格 (RM)",
    category: "カテゴリ",
    eventTitle: "イベント名",
    eventTitleHint: "魅力的なタイトルを入力",
    location: "場所",
    locationHint: "例: Dewan Aspirasi",
    registrationLinkOptional: "登録リンク（任意）",
    eventDescHint: "イベント詳細…（@で登壇者・主催者をタグ付け）",
    privacy: "公開設定",
    publicEvent: "公開イベント",
    starts: "開始",
    ends: "終了",
    select: "選択",
    mustBeAfterStart: "開始より後にしてください",
    searchHint: "投稿・人・商品を検索...",
    startTyping: "入力して検索",
    noResults: "結果が見つかりません",
    showMore: "さらに表示",
    postedBy: "投稿者: {0}",
    replyTo: "Re: {0}",
    notifMentionTitle: "メンションされました",
    notifMentionPostBody: "投稿であなたをメンションしました",
    notifMentionEventTitle: "イベントでタグ付けされました",
    notifMentionEventBody: "イベント説明であなたをメンションしました",
    notifMentionCommentTitle: "コメントでメンションされました",
    notifMentionCommentBody: "返信: {0}",
    notifFollowTitle: "新しいフォロワー",
    notifFollowBody: "{0}さんがあなたをフォローしました。",
  );

  static AppStrings of(AppLanguage lang) => switch (lang) {
        AppLanguage.en => en,
        AppLanguage.ms => ms,
        AppLanguage.ja => ja,
      };
}
