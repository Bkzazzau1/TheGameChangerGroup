# Project instructions

- Do not add explanatory notes, deployment instructions or informational banners to the app UI. Keep setup and deployment guidance in chat, README or documentation unless the user asks for UI text.
- Production web and Android APK builds must include `--dart-define=TGCG_API_URL=https://api.tgcg.online`.
- When making an APK update, use a version code above the last distributed build and preserve the existing package ID and signing identity so users can update without clearing local data.
- Keep private credentials and callback URLs out of source, Git, build artifacts and logs. Files under `build` are not source files to commit.
