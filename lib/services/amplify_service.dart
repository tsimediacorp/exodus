import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../amplify_outputs.dart';

/// One-time Amplify configuration for the Couples-in-Sync backend. Safe to call
/// repeatedly; failures are swallowed so the rest of the (local-first) app keeps
/// working even if the backend is unreachable.
class AmplifyService {
  static bool ready = false;

  static Future<void> configure() async {
    if (ready || Amplify.isConfigured) {
      ready = Amplify.isConfigured;
      return;
    }
    try {
      await Amplify.addPlugins([AmplifyAuthCognito(), AmplifyAPI()]);
      await Amplify.configure(amplifyConfig);
      ready = true;
    } on AmplifyAlreadyConfiguredException {
      ready = true;
    } on Exception catch (e) {
      safePrint('Amplify configure failed: $e');
      ready = false;
    }
  }
}
