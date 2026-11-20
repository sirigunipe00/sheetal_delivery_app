String rupees(num value) => '₹${value.round()}';

String greetingForNow() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String formatWhen(DateTime time) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = time.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${months[local.month - 1]}, $hour:$minute $suffix';
}

String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} d ago';
}

bool isSameDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String explainError(Object error) {
  final raw = error.toString();
  final text = raw.replaceFirst('Exception: ', '');
  final lower = text.toLowerCase();
  if (lower.contains('invalid login') || lower.contains('invalid credentials')) {
    return 'Wrong email or password.';
  }
  if (lower.contains('already registered') || lower.contains('already been registered')) {
    return 'This email is already registered. Log in instead.';
  }
  if (lower.contains('pgrst205') ||
      (lower.contains('drivers') && lower.contains('schema cache')) ||
      lower.contains('could not find the table')) {
    return 'Delivery setup is missing. In Supabase, open the SQL editor and run supabase/create_delivery_schema.sql, then try again.';
  }
  if (lower.contains('driver_id') ||
      lower.contains('delivery_lat') ||
      lower.contains('pgrst204')) {
    return 'The orders table is missing delivery columns. Run supabase/create_delivery_schema.sql in the Supabase SQL editor.';
  }
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('handshakeexception') ||
      lower.contains('connection terminated during handshake') ||
      lower.contains('connection closed before full header') ||
      lower.contains('clientexception')) {
    return 'Could not reach Sheetal servers. Check Wi‑Fi/mobile data and try again.';
  }
  return text;
}
