class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.vehicleNumber,
    required this.isOnline,
    required this.verificationStatus,
    required this.phoneVerified,
    this.vehicleType = 'bike',
    this.licenceNumber = '',
    this.profilePhotoUrl,
    this.address = '',
    this.emergencyContact = '',
    this.rejectionReason,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String vehicleNumber;
  final String vehicleType;
  final String licenceNumber;
  final bool isOnline;
  final String verificationStatus;
  final bool phoneVerified;
  final String? profilePhotoUrl;
  final String address;
  final String emergencyContact;
  final String? rejectionReason;
  final double? latitude;
  final double? longitude;

  bool get isApproved => verificationStatus == 'approved';
  bool get isPendingReview => verificationStatus == 'pending_review';
  bool get isRejected => verificationStatus == 'rejected';
  bool get isDraft => verificationStatus == 'draft' || verificationStatus.isEmpty;
  bool get canGoOnline => isApproved && phoneVerified;

  String get verificationLabel {
    switch (verificationStatus) {
      case 'approved':
        return 'Approved';
      case 'pending_review':
        return 'Pending admin review';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Registration incomplete';
    }
  }

  String get firstName {
    final part = fullName.trim().split(RegExp(r'\s+')).first;
    return part.isEmpty ? 'Partner' : part;
  }

  factory DriverProfile.fromMap(Map<String, dynamic> map) {
    return DriverProfile(
      id: map['id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? 'Partner',
      phone: map['phone']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      vehicleNumber: map['vehicle_number']?.toString() ?? '',
      vehicleType: map['vehicle_type']?.toString() ?? 'bike',
      licenceNumber: map['licence_number']?.toString() ?? '',
      isOnline: map['is_online'] == true,
      verificationStatus: map['verification_status']?.toString() ?? 'draft',
      phoneVerified: map['phone_verified'] == true,
      profilePhotoUrl: map['profile_photo_url']?.toString(),
      address: map['address']?.toString() ?? '',
      emergencyContact: map['emergency_contact']?.toString() ?? '',
      rejectionReason: map['rejection_reason']?.toString(),
      latitude: _asDouble(map['latitude']),
      longitude: _asDouble(map['longitude']),
    );
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class DriverRegistrationDraft {
  String fullName = '';
  String phone = '';
  String email = '';
  String password = '';
  String address = '';
  String emergencyContact = '';
  String vehicleType = 'bike';
  String vehicleNumber = '';
  String licenceNumber = '';
  String upiId = '';
  String accountHolder = '';
  String accountNumber = '';
  String ifsc = '';
  bool phoneVerified = false;
  bool termsAccepted = false;

  /// Local file paths chosen in the wizard (uploaded on submit).
  String? profilePhotoPath;
  String? licencePhotoPath;
  String? rcPhotoPath;
  String? insurancePhotoPath;
}
