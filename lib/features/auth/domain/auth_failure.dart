import '../../../core/errors/app_error.dart';

class AuthFailure extends AppError {
  const AuthFailure(super.message, {super.cause});
}
