import 'package:flutter_dotenv/flutter_dotenv.dart';

/// API keys are read from the .env file at the project root.
/// The .env file is in .gitignore — never commit real keys.
///
/// Expected variables in .env:
///   OPENROUTER_API_KEY=sk-or-v1-...
///   GLM_API_KEY=...           # optional
///   VENICE_API_KEY=...        # optional
///
/// Get an OpenRouter key at https://openrouter.ai/keys.
class ApiKeys {
  static String get openRouter => dotenv.env['OPENROUTER_API_KEY'] ?? '';
  static String get glm        => dotenv.env['GLM_API_KEY'] ?? '';
  static String get venice     => dotenv.env['VENICE_API_KEY'] ?? '';
}
