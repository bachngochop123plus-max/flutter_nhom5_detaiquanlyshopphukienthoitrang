# detai_shopbanphukienthoitrang

## Run with Supabase (recommended)

The app uses an offline-first caching strategy with real-time sync:

1. **On app startup**: Load product list from SQLite cache instantly.
2. **Real-time sync**: Listen to Supabase product changes (INSERT/UPDATE/DELETE).
   - When any change detected → auto-fetch + cache to SQLite.
   - All users see updates within seconds, no manual refresh needed.
3. **In background**: Sync from Supabase to refresh data, then cache to SQLite.
4. **Fallback chain**:
   - Supabase (`SUPABASE_URL` + `SUPABASE_ANON_KEY`) - primary source with real-time
   - `PRODUCTS_API_URL` - fallback when Supabase not configured
   - Local SQLite cache - when network unavailable

**Benefits**:
- App opens instantly (reads SQLite first).
- Real-time updates when admin changes products (no manual refresh).
- Reduces Supabase API requests (cached after first fetch).
- Works offline with cached data.
- Images load on-demand with separate caching (CachedNetworkImage).

### VS Code

Use launch profile `Fashion Shop (Supabase - Default)` in `.vscode/launch.json`.

### Command line

```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

## Data Storage

- **Product metadata** (name, price, category, gallery URLs): Synced to SQLite after Supabase fetch.
- **Product images**: Not stored locally; loaded on-demand via URLs (cached by CachedNetworkImage).
- **Real-time updates**: Automatic via Supabase realtime subscriptions; all users see changes within seconds.
