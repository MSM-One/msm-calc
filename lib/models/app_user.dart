class AppUser {
  final String email;
  final String status;
  final String role;
  final List<String> allowedActions;

  AppUser({
    required this.email,
    required this.status,
    required this.role,
    required this.allowedActions,
  });

  factory AppUser.fromRaw(Map<String, dynamic> map) {
    // Expected fields from Google Sheet: Email, Status, Role, Allowed Actions
    // GAS might return them in different cases or keys depending on how it's written.
    // Based on the prompt: Email, Status, Role, Allowed Actions.

    final email = map['Email']?.toString() ?? map['email']?.toString() ?? "";
    final status =
        map['Status']?.toString() ?? map['status']?.toString() ?? "pending";
    final role = map['Role']?.toString() ?? map['role']?.toString() ?? "User";
    final allowedActionsRaw = map['Allowed Actions']?.toString() ??
        map['allowed_actions']?.toString() ??
        "";

    final allowedActions = allowedActionsRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return AppUser(
      email: email,
      status: status.toLowerCase(),
      role: role,
      allowedActions: allowedActions,
    );
  }

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isAdmin => role.toLowerCase() == 'admin';

  bool hasPermission(String action) {
    if (isAdmin) return true;
    return allowedActions.contains(action);
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'status': status,
      'role': role,
      'allowedActions': allowedActions,
    };
  }
}
