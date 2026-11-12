import '../state/comment_format.dart' show defaultCopyTemplate;
import 'label.dart';

enum DiffMode { unified, split }

/// Persisted user configuration (`$XDG_CONFIG_HOME/patchdeck/settings.json`).
class AppSettings {
  AppSettings({
    required this.themeId,
    required this.codeFontSize,
    required this.diffMode,
    required this.syntaxHighlight,
    required this.labels,
    this.codeFontFamily = '',
    this.copyTemplate = defaultCopyTemplate,
  });

  final String themeId;
  final double codeFontSize;
  final DiffMode diffMode;
  final bool syntaxHighlight;
  final List<ReviewLabel> labels;

  /// Custom monospace family for code; empty uses the system font.
  final String codeFontFamily;

  /// Template used when copying comments (see `formatComment`).
  final String copyTemplate;

  factory AppSettings.defaults() => AppSettings(
    themeId: 'graphite',
    codeFontSize: 13,
    diffMode: DiffMode.unified,
    syntaxHighlight: true,
    labels: [
      ReviewLabel(id: 'bug', title: 'bug', description: 'Comportamiento incorrecto', color: 0xFFE5534B),
      ReviewLabel(id: 'nit', title: 'nit', description: 'Detalle menor / estilo', color: 0xFF8B949E),
      ReviewLabel(id: 'question', title: 'pregunta', description: 'Necesita aclaración', color: 0xFF539BF5),
      ReviewLabel(id: 'perf', title: 'performance', description: 'Impacto en rendimiento', color: 0xFFB083F0),
      ReviewLabel(id: 'security', title: 'seguridad', description: 'Riesgo de seguridad', color: 0xFFE0823D),
      ReviewLabel(id: 'praise', title: 'bien hecho', description: 'Algo que vale la pena destacar', color: 0xFF57AB5A),
    ],
  );

  AppSettings copyWith({
    String? themeId,
    double? codeFontSize,
    DiffMode? diffMode,
    bool? syntaxHighlight,
    List<ReviewLabel>? labels,
    String? codeFontFamily,
    String? copyTemplate,
  }) => AppSettings(
    themeId: themeId ?? this.themeId,
    codeFontSize: codeFontSize ?? this.codeFontSize,
    diffMode: diffMode ?? this.diffMode,
    syntaxHighlight: syntaxHighlight ?? this.syntaxHighlight,
    labels: labels ?? this.labels,
    codeFontFamily: codeFontFamily ?? this.codeFontFamily,
    copyTemplate: copyTemplate ?? this.copyTemplate,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'appearance': {
      'theme': themeId,
      'codeFontSize': codeFontSize,
      'diffMode': diffMode.name,
      'syntaxHighlight': syntaxHighlight,
      'codeFont': codeFontFamily,
    },
    'copy': {'template': copyTemplate},
    'labels': [for (final l in labels) l.toJson()],
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final d = AppSettings.defaults();
    final a = (json['appearance'] as Map?)?.cast<String, dynamic>() ?? const {};
    final labels = json['labels'];
    return AppSettings(
      themeId: a['theme'] as String? ?? d.themeId,
      codeFontSize: ((a['codeFontSize'] as num?)?.toDouble() ?? d.codeFontSize).clamp(10, 22).toDouble(),
      diffMode: DiffMode.values.asNameMap()[a['diffMode']] ?? d.diffMode,
      syntaxHighlight: a['syntaxHighlight'] as bool? ?? d.syntaxHighlight,
      codeFontFamily: a['codeFont'] as String? ?? '',
      copyTemplate: ((json['copy'] as Map?)?['template'] as String?) ?? defaultCopyTemplate,
      labels: labels is List
          ? [for (final l in labels) ReviewLabel.fromJson((l as Map).cast<String, dynamic>())]
          : d.labels,
    );
  }
}
