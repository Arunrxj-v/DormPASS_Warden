/// Permitted student email domain — must match the backend EXACTLY
/// (no substring matching on either side).
///
/// Used by the create-student form. NOTE: this rule applies to STUDENT
/// emails only — warden accounts sign in with a staff username (or any
/// email an administrator linked), so the sign-in screen does not use it.
const String collegeEmailDomain = 'ceconline.edu';

/// True only for a well-formed address whose hostname equals the domain.
bool isCollegeEmail(String value) {
  final email = value.trim().toLowerCase();
  final at = email.lastIndexOf('@');
  if (at <= 0 || at == email.length - 1) return false;
  final hostname = email.substring(at + 1);
  if (hostname != collegeEmailDomain) return false;
  // Reject obvious shape errors: no whitespace, one '@', a dot in the local part.
  if (email.contains(' ') || email.split('@').length != 2) return false;
  return email.length <= 254;
}
