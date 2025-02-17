import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/network_cache_interceptor.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  // Creating a Dio instance and attaching the NetworkCacheInterceptor
  final Dio dio = Dio()
    ..interceptors.add(
      NetworkCacheInterceptor(
        noCacheStatusCodes: [401, 403, 304],
        cacheValidityMinutes: 30,
        getCachedDataWhenError: true,
        uniqueWithHeader: true,
      ),
    );

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Network Cache Example'),
        ),
        body: Center(
          child: FutureBuilder(
            future: fetchData(),
            builder: (context, snapshot) {
              // Show a loading indicator while fetching data
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              // Show an error message if fetching fails
              else if (snapshot.hasError) {
                return Text('Error: \${snapshot.error}');
              }
              // Display fetched data
              else {
                return Text('Data: \${snapshot.data}');
              }
            },
          ),
        ),
      ),
    );
  }

  /// Fetches data from the API with caching enabled
  Future<String> fetchData() async {
    try {
      final response = await dio.get(
        'https://jsonplaceholder.typicode.com/posts/1',
        options: Options(
          extra: {
            'cache': true, // Enable caching
            'validate_time': 60, // Cache validity duration (in minutes)
          },
        ),
      );
      return response.data.toString();
    } catch (e) {
      return 'Failed to fetch data';
    }
  }
}
