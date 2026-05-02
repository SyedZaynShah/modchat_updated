/// Maps Firebase Auth error codes to human-friendly messages
class AuthErrorMapper {
  static String getMessage(String? code) {
    switch (code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'user-not-found':
        return 'No account found with this email.';

      case 'wrong-password':
        return 'Incorrect password. Please try again.';

      case 'email-already-in-use':
        return 'This email is already registered.';

      case 'weak-password':
        return 'Password should be at least 6 characters long.';

      case 'network-request-failed':
        return 'No internet connection. Check your network.';

      case 'too-many-requests':
        return 'Too many attempts. Try again later.';

      case 'operation-not-allowed':
        return 'This operation is not allowed.';

      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'requires-recent-login':
        return 'Please sign in again to continue.';

      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
