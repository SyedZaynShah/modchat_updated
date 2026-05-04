# 🚀 ModChat — A Modern Moderated Messaging Platform

> **ModChat** is a next-generation real-time messaging application designed with **content control, moderation, and performance** at its core.  
Built as a **Final Year Project (FYP)**, ModChat combines modern UI/UX, secure backend architecture, and scalable real-time communication.

---

## ✨ Why ModChat?

Traditional chat apps focus on speed — **ModChat focuses on responsibility**.

✔ Smart moderation  
✔ Secure messaging  
✔ Real-time communication  
✔ Elegant, modern UI  
✔ Scalable architecture  

---

## 📱 Key Features

### 🔐 Authentication
- Firebase Authentication (Email & Password)
- Secure session handling
- User-specific data isolation

### 💬 Messaging
- One-to-one direct messaging
- Real-time updates using Firestore
- Message delivery & seen indicators
- Edit messages (with “Edited” label)
- Delete for me / delete for everyone

### 🎙 Voice Notes
- In-app voice recording
- Duration tracking
- Play, pause, seek functionality
- Clean waveform UI

### 📎 Media & File Sharing
- Images
- Videos
- PDFs
- PPT / DOC / DOCX
- ZIP / RAR
- Stored securely using **Supabase Storage**
- Preview & download support

### 🛡 Moderation & Safety
- Message-level moderation logic
- User-level message hiding
- Safe fallbacks when permissions fail
- Designed for scalable moderation rules

### ⚙ Settings
- Edit bio
- Update profile
- Persistent user preferences

---

## 🎨 UI / UX Philosophy

- **White** base for clarity  
- **Dark navy blue** for structure  
- **Electric blue accents** for emphasis  
- Glassmorphism containers  
- Smooth animations  
- Minimal, modern typography  
- Compact, elegant components (no bulky UI)

Designed to feel **premium, calm, and professional**.

---

## 🏗 Architecture Overview

- **Flutter** — Cross-platform frontend
- **Riverpod** — State management
- **Firebase Auth** — Authentication
- **Cloud Firestore** — Real-time database
- **Supabase Storage** — Media & file storage
- **WebRTC (planned/partial)** — Real-time communication
- **Modular & Layered Architecture**

📌 Clean separation of:
- UI
- Providers
- Services
- Models
- Business logic

---

## How The App Works (High Level)

### App startup and navigation
- `lib/main.dart` initializes Firebase, Supabase, and theme settings.
- Auth state changes rebuild the ProviderScope to avoid cross-account cache.
- `lib/app.dart` wires routes, deep links (group invites), and the AuthGate.

### Core data model (Firestore + Storage)
- Firestore collections:
  - `users` (profiles, block lists, hides, preferences)
  - `dmChats` (DM and group chat metadata)
  - `dmChats/{chatId}/messages` (message documents)
  - `dmChats/{chatId}/members` (group membership + roles)
  - `moderationLogs`, `calls`
- Supabase buckets:
  - `profilePictures` (avatars)
  - `chatMedia` (images, videos, files)
  - `dmMedia` (voice notes)
  - `groupImages` (group avatars)

### How messages travel (DM)
1. UI (`InputField`) calls `ChatService.sendText` / `sendMedia` / `sendPoll`.
2. `ChatService` writes a message doc in `dmChats/{chatId}/messages`.
3. Media sends are optimistic: message appears immediately, then upload runs.
4. Uploads go to Supabase Storage, then Firestore updates `bucket`,
   `mediaPath`, `storagePath`, `uploadStatus`, and `uploadProgress`.
5. `messagesProvider` streams updates from Firestore and filters:
   - membership window
   - delete-for-me hides
   - visible-to restrictions
6. `ChatDetailScreen` groups messages into blocks, renders bubbles,
   reactions, replies, pins, and unread divider.
7. Read/delivery sync:
   - `acknowledgeDelivered` marks delivered
   - `markAllSeen` marks seen
   - `updateLastRead` maintains `lastRead` for unread tracking

### Media and voice notes
- Media URL resolution goes through `MediaResolver` / `MediaUrlResolver`.
- `FilePreviewWidget` handles media previews, audio playback, and caching.
- `VoiceNoteService` prewarms players and caches audio with backoff retry.
- `AudioRecorderWidget` records AAC/m4a, then sends via `ChatService`.

### Groups and moderation (overview)
- Group chats use the same message collection, but with a `members` subcol.
- `GroupModerationService` enforces roles, permissions, and approvals.
- `BlockService` controls DM blocking and user-level protections.

---

## 📂 Project Structure (Key Files)

### Entry and routing
- `lib/main.dart`: bootstrap Firebase, Supabase, theme, auth-driven scope
- `lib/app.dart`: routes, deep links, AuthGate, screen wiring

### Models
- `lib/models/message_model.dart`: message schema + type inference
- `lib/models/user_model.dart`: user profile schema
- `lib/models/reply_target.dart`: reply metadata for threaded preview

### Providers (Riverpod)
- `lib/providers/auth_providers.dart`: auth + Firestore service providers
- `lib/providers/chat_providers.dart`: message streams, block status, chat list
- `lib/providers/user_providers.dart`: user document streams

### Services (business logic)
- `lib/services/chat_service.dart`: send/edit/delete/pin/react/read receipts
- `lib/services/firestore_service.dart`: Firestore collection access
- `lib/services/storage_service.dart`: Supabase upload helpers + bucket names
- `lib/services/supabase_service.dart`: signed URL resolver (legacy/compat)
- `lib/services/media_resolver.dart`: storage path to public URL
- `lib/services/media_url_resolver.dart`: strict URL normalization (new)
- `lib/services/voice_note_service.dart`: audio caching + prewarm
- `lib/services/typing_controller.dart`: typing/recording presence
- `lib/services/block_service.dart`: block/unblock logic

### Screens (UI)
- `lib/screens/chat/chat_detail_screen.dart`: DM message view and actions
- `lib/screens/chat/group_chat_detail_screen.dart`: group message view
- `lib/screens/home/home_screen.dart`: entry after auth
- `lib/screens/auth/*`: login, signup, verification, landing
- `lib/screens/group/*`: group create, settings, moderation dashboard

### Widgets (UI building blocks)
- `lib/widgets/input_field.dart`: text/media/poll/voice composer
- `lib/widgets/file_preview_widget.dart`: image/video/file/audio rendering
- `lib/widgets/audio_recorder_widget.dart`: voice recording UI
- `lib/widgets/message_interaction_overlay.dart`: reply/copy/edit actions
- `lib/widgets/reply_preview_bar.dart`: reply target preview
- `lib/widgets/swipe_to_reply.dart`: gesture-driven replies


---

## 🔐 Firestore Security Rules (Concept)

- Users can only edit their own profiles
- Only chat members can:
  - Read chats
  - Send messages
  - Edit or delete messages
- Safe fallbacks prevent crashes
- Designed for real-world scalability

---

## 🧪 Tested On

- Android 11+
- Physical Android devices
- Firebase production environment
- Supabase production storage

---

## 🛠 Tech Stack

| Technology | Purpose |
|---------|--------|
| Flutter | UI & App Logic |
| Riverpod | State Management |
| Firebase Auth | Authentication |
| Cloud Firestore | Real-time Database |
| Supabase | Media Storage |
| WebRTC | Voice / Media (Partial) |

---

## 🎓 Academic Context

- **Final Year Project (FYP)**
- Bachelor of Science in Computer Science
- Core focus areas:
  - Software Architecture
  - Secure Systems
  - Real-Time Applications
  - UI/UX Engineering

---

## 🌱 Future Enhancements

- AI-based toxicity detection
- Group chats with roles
- Admin moderation dashboard
- End-to-end encryption
- Calls and WebRTC full rollout

---

## 🧠 What This Project Demonstrates

✔ Real-world application architecture  
✔ Firebase security & rules design  
✔ State management expertise  
✔ Clean and modern UI engineering  
✔ Production-level debugging  
✔ Scalable system design thinking  

---

## 👨‍💻 Author

**Zain (Shah Sahib)**  
BS Computer Science  
Final Year Project — 2025–2026  

> *“I didn’t just build an app.  
I built a system.”*

---

## ⭐ Support

If you find this project useful:
- ⭐ Star the repository  
- 🍴 Fork it  
- 🧠 Learn from it  

---

## 📜 License

This project is intended for **academic and learning purposes**.  
Commercial usage requires permission.

---

🔥 **ModChat — Where Messaging Meets Responsibility.**


