import 'package:dio/dio.dart';

void main() async {
  var res = await Dio().get('https://maps.googleapis.com/maps/api/geocode/json?latlng=8.5147,81.1856&key=AIzaSyAxGlCCI4yoOn3umPPyX1VypSzL2Sutz9U');
  print(res.data);
}
