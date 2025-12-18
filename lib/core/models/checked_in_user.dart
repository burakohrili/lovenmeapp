class CheckedInUser {
  final String id;
  final String name;
  final int age;
  final String? photoUrl;
  final String? profession;
  final DateTime checkedInAt;
  final bool isPremium;
  final bool isMuhtar;
  final int totalCheckIns;

  CheckedInUser({
    required this.id,
    required this.name,
    required this.age,
    this.photoUrl,
    this.profession,
    required this.checkedInAt,
    this.isPremium = false,
    this.isMuhtar = false,
    this.totalCheckIns = 1,
  });

  factory CheckedInUser.fromMap(Map<String, dynamic> map, String id) {
    return CheckedInUser(
      id: id,
      name: map['name'] ?? '',
      age: map['age'] ?? 0,
      photoUrl: map['photoUrl'],
      profession: map['profession'],
      checkedInAt: map['checkedInAt']?.toDate() ?? DateTime.now(),
      isPremium: map['isPremium'] ?? false,
      isMuhtar: map['isMuhtar'] ?? false,
      totalCheckIns: map['totalCheckIns'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'age': age,
      'photoUrl': photoUrl,
      'profession': profession,
      'checkedInAt': checkedInAt,
      'isPremium': isPremium,
      'isMuhtar': isMuhtar,
      'totalCheckIns': totalCheckIns,
    };
  }
}
