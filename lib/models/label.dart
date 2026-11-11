import 'package:flutter/painting.dart';

/// A user-defined tag that can be attached to review comments.
class ReviewLabel {
  ReviewLabel({
    required this.id,
    required this.title,
    this.description = '',
    required this.color,
  });

  final String id;
  final String title;
  final String description;
  final int color;

  Color get colorValue => Color(color);

  ReviewLabel copyWith({String? title, String? description, int? color}) =>
      ReviewLabel(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        color: color ?? this.color,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'color': '#${(color & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}',
      };

  factory ReviewLabel.fromJson(Map<String, dynamic> json) => ReviewLabel(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        color: parseColor(json['color']) ?? 0xFF8B949E,
      );

  static int? parseColor(Object? v) {
    if (v is int) return v;
    if (v is! String) return null;
    var s = v.trim().replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    return int.tryParse(s, radix: 16);
  }
}
