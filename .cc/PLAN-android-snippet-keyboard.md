# Android Snippet Keyboard IME

Custom Android keyboard for managing and inserting text snippets.

## Goal

A keyboard that lets users:
- Search through saved text snippets
- Tap to paste snippet into any text field
- Add/edit/delete snippets

## Architecture

```
app/
├── SnippetKeyboardService.kt   # InputMethodService implementation
├── ui/
│   ├── KeyboardView.kt         # Main keyboard layout
│   ├── SnippetListAdapter.kt   # RecyclerView adapter
│   └── SnippetSearchBar.kt     # Search input
├── data/
│   ├── Snippet.kt              # Data class
│   ├── SnippetDao.kt           # Room DAO
│   └── SnippetDatabase.kt      # Room database
└── SnippetManagerActivity.kt   # Standalone UI for managing snippets
```

## Implementation Steps

### Phase 1: Minimal Keyboard
- [ ] Create new Android project (min SDK 24)
- [ ] Implement basic `InputMethodService`
- [ ] Create simple keyboard view with hardcoded snippets
- [ ] Wire up `InputConnection.commitText()` to insert text
- [ ] Add to manifest with `android.permission.BIND_INPUT_METHOD`

### Phase 2: Encrypted Storage
- [ ] Add Room database for snippets
- [ ] Integrate SQLCipher for database encryption
- [ ] Generate/store encryption key in Android Keystore
- [ ] Create Snippet entity (id, title, content, tags, lastUsed, isSecret)
- [ ] Build SnippetDao with search query
- [ ] Connect keyboard view to database

### Phase 3: Search & UI
- [ ] Add search bar to keyboard view
- [ ] Implement real-time filtering
- [ ] Style the snippet list (title preview, tap to insert)
- [ ] Add "switch to regular keyboard" button

### Phase 4: Management
- [ ] Create standalone Activity for snippet CRUD
- [ ] Import/export snippets (encrypted JSON or password-protected)
- [ ] Categories/folders (optional)
- [ ] Optional biometric lock for sensitive snippets

## Key Code Snippets

### Manifest Declaration
```xml
<service
    android:name=".SnippetKeyboardService"
    android:permission="android.permission.BIND_INPUT_METHOD">
    <intent-filter>
        <action android:name="android.view.InputMethod" />
    </intent-filter>
    <meta-data
        android:name="android.view.im"
        android:resource="@xml/method" />
</service>
```

### Insert Text
```kotlin
fun insertSnippet(content: String) {
    currentInputConnection?.commitText(content, 1)
}
```

### Search Query (Room)
```kotlin
@Query("SELECT * FROM snippets WHERE title LIKE '%' || :query || '%' OR content LIKE '%' || :query || '%' ORDER BY lastUsed DESC")
fun search(query: String): Flow<List<Snippet>>
```

## Security / Encryption

### Dependencies
```kotlin
// build.gradle.kts
implementation("net.zetetic:android-database-sqlcipher:4.5.4")
implementation("androidx.sqlite:sqlite-ktx:2.4.0")
```

### Keystore Key Generation
```kotlin
object KeystoreManager {
    private const val KEY_ALIAS = "snippet_db_key"

    fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

        keyStore.getEntry(KEY_ALIAS, null)?.let {
            return (it as KeyStore.SecretKeyEntry).secretKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false) // or true for biometric unlock
                .build()
        )
        return keyGenerator.generateKey()
    }
}
```

### Encrypted Room Database
```kotlin
fun getEncryptedDatabase(context: Context): SnippetDatabase {
    val passphrase = getPassphraseFromKeystore()
    val factory = SupportFactory(passphrase)

    return Room.databaseBuilder(context, SnippetDatabase::class.java, "snippets.db")
        .openHelperFactory(factory)
        .build()
}
```

### Optional: Biometric Unlock
- Set `setUserAuthenticationRequired(true)` on key
- Prompt BiometricPrompt before database access
- Good for high-security snippets (passwords, keys)

## Tech Stack

- Kotlin
- Jetpack Compose (for keyboard UI)
- Room + SQLCipher (encrypted SQLite)
- Android Keystore (key management)
- Hilt (DI, optional)
- Material 3

## Notes

- Test on physical device (emulator keyboard switching is awkward)
- Consider adding a "quick switch" key to toggle back to default keyboard
- Snippet sync across devices could use Firebase or simple file export
