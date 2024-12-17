import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:network_cache_interceptor/network_cache_interceptor.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final Dio dio = Dio()..interceptors.add(NetworkCacheInterceptor());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Network Cache Example'),
        ),
        body: Center(
          child: FutureBuilder(
            future: fetchData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              } else {
                return Text('Data: ${snapshot.data}');
              }
            },
          ),
        ),
      ),
    );
  }

  Future<String> fetchData() async {
    try {
      final response = await dio.get(
        'https://jsonplaceholder.typicode.com/posts/1',
        options: Options(
          extra: {
            'cache': true,
            'validate_time': 60, // Cache validity in minutes
          },
        ),
      );
      return response.data.toString();
    } catch (e) {
      return 'Failed to fetch data';
    }
  }
}