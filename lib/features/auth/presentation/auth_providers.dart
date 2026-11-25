import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_gateway.dart';
import '../domain/auth_session.dart';

final authGatewayProvider = Provider<AuthGateway?>((ref) => null);

final authConfigurationErrorProvider = Provider<String?>((ref) => null);

final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  final gateway = ref.watch(authGatewayProvider);
  if (gateway == null) return Stream.value(null);

  return Stream.multi((controller) {
    controller.add(gateway.currentSession);
    final subscription = gateway.sessionChanges.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = subscription.cancel;
  });
});

final authPasswordRecoveryProvider = StreamProvider<bool>((ref) {
  final gateway = ref.watch(authGatewayProvider);
  if (gateway == null) return Stream.value(false);
  return gateway.passwordRecoveryChanges;
});
