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

## 📂 Project Structure (Simplified)
lib/
│── auth/
│ ├── login_screen.dart
│ ├── signup_screen.dart
│
│── chat/
│ ├── chat_screen.dart
│ ├── chat_service.dart
│ ├── chat_providers.dart
│
│── ui/
│ ├── widgets/
│ ├── theme/
│
│── providers/
│── models/
│── main.dart


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
- Message reactions
- User blocking & reporting

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


