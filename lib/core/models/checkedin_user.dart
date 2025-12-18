class CheckedInUser {
  final String userId;
  final String userName;
  final String? userPhoto;
  final DateTime checkInTime;
  final double latitude;
  final double longitude;
  final bool fromFavorite;
  final bool isMayor;
  final String? mayorType; // 'first_checkin' or 'diamond'
  final bool isClickable; // Profil tıklanabilir mi?
  final bool canMessage; // Mesaj atılabilir mi?
  final int totalCheckIns; // Toplam check-in sayısı

  CheckedInUser({
    required this.userId,
    required this.userName,
    this.userPhoto,
    required this.checkInTime,
    required this.latitude,
    required this.longitude,
    this.fromFavorite = false,
    this.isMayor = false,
    this.mayorType,
    this.isClickable = true,
    this.canMessage = true,
    this.totalCheckIns = 1,
  });

  factory CheckedInUser.fromMap(Map<String, dynamic> map) {
    return CheckedInUser(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userPhoto: map['userPhoto'],
      checkInTime: map['checkInTime']?.toDate() ?? DateTime.now(),
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      fromFavorite: map['fromFavorite'] ?? false,
      isMayor: map['isMayor'] ?? false,
      mayorType: map['mayorType'],
      isClickable: map['isClickable'] ?? true,
      canMessage: map['canMessage'] ?? true,
      totalCheckIns: map['totalCheckIns'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhoto': userPhoto,
      'checkInTime': checkInTime,
      'latitude': latitude,
      'longitude': longitude,
      'fromFavorite': fromFavorite,
      'isMayor': isMayor,
      'mayorType': mayorType,
      'isClickable': isClickable,
      'canMessage': canMessage,
      'totalCheckIns': totalCheckIns,
    };
  }

  // JSON serialization for caching
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhoto': userPhoto,
      'checkInTime': checkInTime.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'fromFavorite': fromFavorite,
      'isMayor': isMayor,
      'mayorType': mayorType,
      'isClickable': isClickable,
      'canMessage': canMessage,
      'totalCheckIns': totalCheckIns,
    };
  }

  factory CheckedInUser.fromJson(Map<String, dynamic> json) {
    return CheckedInUser(
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      userPhoto: json['userPhoto'],
      checkInTime: DateTime.fromMillisecondsSinceEpoch(json['checkInTime'] ?? 0),
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      fromFavorite: json['fromFavorite'] ?? false,
      isMayor: json['isMayor'] ?? false,
      mayorType: json['mayorType'],
      isClickable: json['isClickable'] ?? true,
      canMessage: json['canMessage'] ?? true,
      totalCheckIns: json['totalCheckIns'] ?? 1,
    );
  }

  // Convenience getters for compatibility
  String get id => userId;
  String get name => userName;
  String? get photoUrl => userPhoto;
  bool get isPremium => false; // Default to false, can be overridden if needed
}
