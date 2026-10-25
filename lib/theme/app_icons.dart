import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons_600.dart';

/// Every icon the app uses, by meaning. Screens use `AppIcons.x`, never an
/// icon library directly, so the set can be swapped in one place.
///
/// Library: Lucide (outlined, 2px stroke). Lucide has no filled glyphs, so
/// the `…Filled` variants (selected nav tabs, active toggles) use the
/// heavier 600-weight stroke instead.
abstract final class AppIcons {
  // --- Navigation ---
  static const IconData home = LucideIcons.house;
  static const IconData homeFilled = LucideIcons600.house;
  static const IconData market = LucideIcons.store;
  static const IconData marketFilled = LucideIcons600.store;
  static const IconData events = LucideIcons.calendar;
  static const IconData eventsFilled = LucideIcons600.calendar;
  static const IconData profile = LucideIcons.circleUser;
  static const IconData profileFilled = LucideIcons600.circleUser;
  static const IconData search = LucideIcons.search;
  static const IconData searchFilled = LucideIcons600.search;
  static const IconData create = LucideIcons.plus;
  static const IconData notifications = LucideIcons.bell;
  static const IconData notificationsActive = LucideIcons.bellRing;
  static const IconData notificationsOff = LucideIcons.bellOff;
  static const IconData settings = LucideIcons.settings;
  static const IconData menu = LucideIcons.menu;
  static const IconData back = LucideIcons.arrowLeft;
  static const IconData forward = LucideIcons.arrowRight;
  static const IconData close = LucideIcons.x;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData up = LucideIcons.chevronUp;
  static const IconData down = LucideIcons.chevronDown;
  static const IconData externalLink = LucideIcons.externalLink;

  // --- Content actions ---
  static const IconData comment = LucideIcons.messageCircle;
  static const IconData like = LucideIcons.heart;
  static const IconData save = LucideIcons.bookmark;
  static const IconData saved = LucideIcons600.bookmarkCheck;
  static const IconData share = LucideIcons.share2;
  static const IconData repost = LucideIcons.repeat2;
  static const IconData more = LucideIcons.ellipsisVertical;
  static const IconData moreHorizontal = LucideIcons.ellipsis;
  static const IconData send = LucideIcons.send;
  static const IconData edit = LucideIcons.pencil;
  static const IconData compose = LucideIcons.squarePen;
  static const IconData delete = LucideIcons.trash2;
  static const IconData report = LucideIcons.flag;
  static const IconData copy = LucideIcons.copy;
  static const IconData link = LucideIcons.link;
  static const IconData download = LucideIcons.download;
  static const IconData upload = LucideIcons.upload;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData filter = LucideIcons.slidersHorizontal;
  static const IconData sort = LucideIcons.funnel;
  static const IconData grid = LucideIcons.layoutGrid;
  static const IconData list = LucideIcons.list;
  static const IconData check = LucideIcons.check;

  // --- Status / meaning ---
  static const IconData pin = LucideIcons.pin;
  static const IconData verified = LucideIcons.badgeCheck;
  static const IconData official = LucideIcons.shieldCheck;
  static const IconData anonymous = LucideIcons.eyeOff;
  static const IconData visible = LucideIcons.eye;
  static const IconData lock = LucideIcons.lock;
  static const IconData info = LucideIcons.info;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData error = LucideIcons.circleAlert;
  static const IconData success = LucideIcons.circleCheck;
  static const IconData cancel = LucideIcons.circleX;
  static const IconData history = LucideIcons.history;
  static const IconData announcement = LucideIcons.megaphone;
  static const IconData moderation = LucideIcons.shield;
  static const IconData sparkle = LucideIcons.sparkles;

  // --- Events / market details ---
  static const IconData location = LucideIcons.mapPin;
  static const IconData calendar = LucideIcons.calendar;
  static const IconData calendarAdd = LucideIcons.calendarPlus;
  static const IconData calendarJoined = LucideIcons.calendarCheck;
  static const IconData clock = LucideIcons.clock;
  static const IconData ticket = LucideIcons.ticket;
  static const IconData price = LucideIcons.tag;
  static const IconData sold = LucideIcons.badgeDollarSign;
  static const IconData bag = LucideIcons.shoppingBag;
  static const IconData wallet = LucideIcons.wallet;
  static const IconData qrCode = LucideIcons.qrCode;
  static const IconData scan = LucideIcons.scanLine;
  static const IconData hashtag = LucideIcons.hash;
  static const IconData mention = LucideIcons.atSign;

  // --- People ---
  static const IconData person = LucideIcons.user;
  static const IconData people = LucideIcons.users;
  static const IconData follow = LucideIcons.userPlus;
  static const IconData following = LucideIcons.userCheck;
  static const IconData phone = LucideIcons.phone;
  static const IconData email = LucideIcons.mail;
  static const IconData website = LucideIcons.globe;

  // --- Media ---
  static const IconData camera = LucideIcons.camera;
  static const IconData photo = LucideIcons.image;

  // --- Settings / account ---
  static const IconData theme = LucideIcons.palette;
  static const IconData language = LucideIcons.languages;
  static const IconData login = LucideIcons.logIn;
  static const IconData logout = LucideIcons.logOut;
}
