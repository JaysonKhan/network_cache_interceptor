import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/cupertino.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Database helper class to handle caching
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
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS responses (
        request STRING PRIMARY KEY,
        response TEXT,
        timestamp STRING
      )
    ''');
  }

  Future<void> insertResponse(
      String request, Map<String, dynamic> response) async {
    try {
      Database db = await database;
      final responseString = jsonEncode(response);
      await db.insert(
        'responses',
        {
          'request': request,
          'response': responseString,
          'timestamp': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace, // Replace on conflict
      );
    } catch (e) {
      log('Error inserting response: $e');
    }
  }

  Future<Map<String, dynamic>> getResponse(String request) async {
    try {
      Database db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'responses',
        where: 'request = ?',
        whereArgs: [request],
      );
      return maps.isNotEmpty
          ? jsonDecode(maps.first['response'] as String)
          : {};
    } catch (e) {
      log('Error fetching response: $e');
      return {};
    }
  }

  Future<void> clearDatabase() async {
    Database db = await database;
    await db.execute('DELETE FROM responses');
  }

  FutureOr<void> _onUpgrade(Database db, int oldVersion, int newVersion) {
    if (oldVersion < 2) {
      db.execute('DROP TABLE IF EXISTS responses');
      _onCreate(db, newVersion);
    }
  }
}
