import 'package:dio/dio.dart';

final class Article {
  const Article({
    required this.id,
    required this.authorId,
    required this.title,
    required this.body,
  });

  final int id;
  final int authorId;
  final String title;
  final String body;

  factory Article.fromJson(Map<String, dynamic> json) => Article(
    id: json['id'] as int,
    authorId: json['userId'] as int,
    title: json['title'] as String,
    body: json['body'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is Article &&
      other.id == id &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, title, body);
}

final class NewsApi {
  const NewsApi(this._dio);

  final Dio _dio;

  Future<List<Article>> fetchAll() async {
    final response = await _dio.get<List<dynamic>>('/posts');
    final data = response.data ?? const [];
    return data
        .map((e) => Article.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Article>> searchByAuthor(int authorId) async {
    final response = await _dio.get<List<dynamic>>(
      '/posts',
      queryParameters: {'userId': authorId},
    );
    final data = response.data ?? const [];
    return data
        .map((e) => Article.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
