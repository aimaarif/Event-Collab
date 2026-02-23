/// API configuration for Hugging Face Inference API (free tier).
/// Get your token at: https://huggingface.co/settings/tokens
/// Set via: flutter run --dart-define=HF_TOKEN=your_token
const String huggingFaceApiToken = String.fromEnvironment(
  'HF_TOKEN',
  defaultValue: '',
);
