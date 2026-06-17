import 'dart:convert';
import 'package:http/http.dart' as http;

class SongService {
  static Future<String> analyzeLyrics(List<String> lyrics) async {
    final response = await http.post(
      Uri.parse("http://127.0.0.1:5000/analyze"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"lyrics": lyrics}),
    );

    final data = jsonDecode(response.body);
    return data["result"];
  }
}
