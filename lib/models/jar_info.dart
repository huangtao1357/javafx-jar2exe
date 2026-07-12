enum MainClassType { manifest, mainMethod, javafxApplication }

class MainClassEntry {
  final String className;
  final MainClassType type;

  const MainClassEntry({required this.className, required this.type});

  String get label {
    final tag = switch (type) {
      MainClassType.manifest => '[manifest]',
      MainClassType.mainMethod => '[main]',
      MainClassType.javafxApplication => '[JavaFX]',
    };
    return '$tag $className';
  }

  Map<String, dynamic> toJson() => {'className': className, 'type': type.name};

  factory MainClassEntry.fromJson(Map<String, dynamic> json) => MainClassEntry(
        className: json['className'] as String,
        type: MainClassType.values.byName(json['type'] as String),
      );
}

class JarInfo {
  final String path;
  final String moduleName;
  final String? manifestMainClass;
  final List<MainClassEntry> candidateEntries;
  final bool isModular;
  final bool needsJavaFxSdk;

  const JarInfo({
    required this.path,
    required this.moduleName,
    required this.candidateEntries,
    this.manifestMainClass,
    this.isModular = false,
    this.needsJavaFxSdk = false,
  });

  List<MainClassEntry> get selectableEntries => candidateEntries;

  MainClassEntry? get defaultEntry {
    if (manifestMainClass == null) {
      return candidateEntries.firstOrNull;
    }
    return candidateEntries.firstWhere(
      (e) => e.className == manifestMainClass,
      orElse: () => candidateEntries.first,
    );
  }
}
