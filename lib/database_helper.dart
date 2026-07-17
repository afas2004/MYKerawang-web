import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// NOTE: sqflite does not support web. On web the cache is simply skipped —
// the app falls back to fetching directly from Supabase, which is fine
// because this DB is only an offline cache.

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mykerawang_cache.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // Cache Listings
    await db.execute('''
      CREATE TABLE listings (
        id TEXT PRIMARY KEY,
        title TEXT,
        description TEXT,
        price REAL,
        category TEXT,
        image_url TEXT,
        seller_id TEXT,
        is_sold INTEGER
      )
    ''');
    
    // Cache Events
    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        title TEXT,
        location TEXT,
        start_datetime TEXT,
        image_url TEXT,
        organizer_id TEXT
      )
    ''');
  }

  // UPSERT METHODS (Save Supabase data to local phone)
  Future<void> cacheListings(List<Map<String, dynamic>> items) async {
    if (kIsWeb) return; // No local cache on web
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('listings'); // Clear old cache
      for (var item in items) {
        await txn.insert('listings', {
          'id': item['id'],
          'title': item['title'],
          'description': item['description'],
          'price': item['price'],
          'category': item['category'],
          'image_url': item['image_url'],
          'seller_id': item['seller_id'],
          'is_sold': (item['is_sold'] ?? false) ? 1 : 0,
        });
      }
    });
  }

  Future<void> cacheEvents(List<Map<String, dynamic>> items) async {
    if (kIsWeb) return; // No local cache on web
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('events');
      for (var item in items) {
        await txn.insert('events', {
          'id': item['id'],
          'title': item['title'],
          'location': item['location'],
          'start_datetime': item['start_datetime'],
          'image_url': item['image_url'],
          'organizer_id': item['organizer_id'],
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedListings() async {
    if (kIsWeb) return []; // No local cache on web
    final db = await instance.database;
    return await db.query('listings');
  }

  Future<List<Map<String, dynamic>>> getCachedEvents() async {
    if (kIsWeb) return []; // No local cache on web
    final db = await instance.database;
    return await db.query('events');
  }
}