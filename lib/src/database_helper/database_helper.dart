import 'dart:async';
import 'dart:developer';

import 'package:flutter/cupertino.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Database helper class to handle caching.
///
/// Stores one row per cache entry:
/// * `request`   — the full cache key (may be encrypted).
/// * `url`       — an endpoint tag (base URL + path, may be encrypted) used for
///   targeted invalidation via [deleteByUrl].
/// * `key_hash`  — a fingerprint of the encryption key, used to detect key
///   rotation and drop entries that can no longer be decrypted.
/// * `response`  — the stored payload (may be encrypted).
/// * `timestamp` — insertion time, used for expiry and eviction.
class NetworkCacheSQLHelper {
  static final NetworkCacheSQLHelper _instance =
      NetworkCacheSQLHelper._internal();
  static Database? _database;

  factory NetworkCacheSQLHelper() {
    return _instance;
  }

  NetworkCacheSQLHelper._internal();

  @visibleForTesting
  NetworkCacheSQLHelper.testing();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'network_cache.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS responses (
        request TEXT PRIMARY KEY,
        url TEXT,
        key_hash TEXT,
        response TEXT,
        timestamp TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_responses_url ON responses(url)',
    );
  }

  /// Inserts (or replaces) a cache entry.
  Future<void> insertResponse({
    required String request,
    required String url,
    required String keyHash,
    required String response,
  }) async {
    try {
      Database db = await database;
      await db.insert(
        'responses',
        {
          'request': request,
          'url': url,
          'key_hash': keyHash,
          'response': response,
          'timestamp': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      log('Error inserting response: $e');
    }
  }

  /// Retrieves a cached row by its [request] key.
  ///
  /// Returns the full row (`response`, `key_hash`, `timestamp`, ...), or an
  /// empty map when nothing is found.
  Future<Map<String, dynamic>> getResponse(String request) async {
    try {
      Database db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'responses',
        where: 'request = ?',
        whereArgs: [request],
      );
      return maps.isNotEmpty ? maps.first : {};
    } catch (e) {
      log('Error fetching response: $e');
      return {};
    }
  }

  /// Deletes a single entry by its [request] key.
  Future<void> deleteResponse(String request) async {
    try {
      Database db = await database;
      await db.delete('responses', where: 'request = ?', whereArgs: [request]);
    } catch (e) {
      log('Error deleting response: $e');
    }
  }

  /// Deletes every entry whose endpoint tag equals [url].
  Future<int> deleteByUrl(String url) async {
    try {
      Database db = await database;
      return await db.delete('responses', where: 'url = ?', whereArgs: [url]);
    } catch (e) {
      log('Error invalidating by url: $e');
      return 0;
    }
  }

  /// Deletes every entry whose key fingerprint differs from [keyHash].
  ///
  /// Used to purge entries that were written under a different encryption key
  /// (or in a different encryption on/off state), since they can no longer be
  /// read back.
  Future<int> deleteByKeyHashNot(String keyHash) async {
    try {
      Database db = await database;
      return await db.delete(
        'responses',
        where: 'key_hash != ?',
        whereArgs: [keyHash],
      );
    } catch (e) {
      log('Error pruning entries by key hash: $e');
      return 0;
    }
  }

  /// Deletes every entry older than [cutoff].
  Future<int> deleteExpired(DateTime cutoff) async {
    try {
      Database db = await database;
      return await db.delete(
        'responses',
        where: 'timestamp < ?',
        whereArgs: [cutoff.toIso8601String()],
      );
    } catch (e) {
      log('Error deleting expired entries: $e');
      return 0;
    }
  }

  /// Keeps only the [maxEntries] most recent rows, deleting the rest.
  Future<void> enforceMaxEntries(int maxEntries) async {
    if (maxEntries <= 0) return;
    try {
      Database db = await database;
      await db.rawDelete(
        '''
        DELETE FROM responses
        WHERE request NOT IN (
          SELECT request FROM responses
          ORDER BY timestamp DESC
          LIMIT ?
        )
        ''',
        [maxEntries],
      );
    } catch (e) {
      log('Error enforcing max entries: $e');
    }
  }

  /// Returns the number of cached entries.
  Future<int> count() async {
    try {
      Database db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) AS c FROM responses');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      log('Error counting entries: $e');
      return 0;
    }
  }

  Future<void> clearDatabase() async {
    Database db = await database;
    await db.execute('DELETE FROM responses');
  }

  FutureOr<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // The cache is disposable, so a schema change simply rebuilds the table.
    if (oldVersion < newVersion) {
      await db.execute('DROP INDEX IF EXISTS idx_responses_url');
      await db.execute('DROP TABLE IF EXISTS responses');
      await _onCreate(db, newVersion);
    }
  }
}
