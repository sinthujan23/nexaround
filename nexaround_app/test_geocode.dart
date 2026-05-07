import 'package:dio/dio.dart';

void main() async {
  var res = await Dio().get('https://maps.googleapis.com/maps/api/geocode/json?latlng=8.5147,81.1856&key=AIzaSyDV7xSXzCp8tt4BqrjvHqfRyexT9Dhk-jw');
  print(res.data);
}
