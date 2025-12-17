# 🛠️ 開發者文件 (Developer Guide)

本文件說明「會議簽到與投票系統」的技術架構、資料流設計與開發環境設定。

## 🏗️ 專案架構 (Project Structure)

本專案採用 **MVC (Model-View-Controller)** 的變體架構進行模組化拆分，以提升程式碼的可維護性。

```text
lib/
├── main.dart                   # 程式入口點 (包含 Theme 設定)
├── models/                     # [Model] 資料模型定義
│   └── meeting_models.dart     # 定義 User, Meeting, VoteSession 等類別
├── services/                   # [Controller/Service] 業務邏輯與資料存取
│   └── data_service.dart       # 單例模式 (Singleton) 的資料管理器
├── widgets/                    # [View] 共用 UI 元件
│   └── custom_radio_tile.dart  # 自定義 Radio 元件
└── screens/                    # [View] 各個頁面
    ├── home_screen.dart            # 首頁 & 建立會議彈窗 (CSV 處理邏輯在此)
    ├── meeting_selection_screen.dart # 會議列表選擇頁
    ├── role_selection_screen.dart    # 身分選擇頁 (模擬登入)
    ├── meeting_room_screen.dart      # 會議室主畫面 (包含 TabView、投票邏輯)
    └── dashboard_screen.dart         # 儀表板畫面 (可獨立或嵌入顯示)
```

## 🧠 核心邏輯說明

### 1. 資料管理 (Data Service)
- **Singleton Pattern**：`DataService` 為全域單例，確保在不同頁面切換時資料一致。
- **多會議管理**：`meetings` 列表儲存所有會議物件，`currentMeeting` 指向當前操作的會議。

### 2. 投票權計算 (Voting Eligibility)
位於 `DataService.performRollCall()` 與 `castVote()`。
- **基本權限**：身分為「出席」且狀態為「已簽到」，經清點後 `hasVotingRight` 為 true。
- **迴避原則**：
    - 發起投票時，主席可勾選 `excludedUserIds`。
    - 即使 `hasVotingRight` 為 true，若 User ID 在 `excludedUserIds` 中，則該次投票無權操作。

### 3. 棄權與分母計算
為了確保數據精確，採用 **快照 (Snapshot)** 機制：
- **進行中**：分母 = `目前具投票權人數` - `迴避人數` (動態變動)。
- **結束時**：系統將當下的分母寫入 `VoteSession.eligibleVotersCount` (永久鎖定)。
- **棄權公式**：`abstentionCount` = `eligibleVotersCount` - `totalVotes`。

### 4. 檔案處理 (CSV Import)
- 使用 `file_picker` 套件選取檔案。
- 使用 `dart:io` 讀取檔案內容。
- 相容 Android (Scoped Storage) 與 Windows 檔案路徑。

## 📦 依賴套件 (Dependencies)

請確保 `pubspec.yaml` 包含以下套件：

| 套件名稱 | 用途 |
| :--- | :--- |
| `file_picker` | 讀取手機/電腦上的 CSV 檔案 |
| `path_provider` | 取得暫存資料夾路徑 (用於生成範例檔) |
| `share_plus` | 呼叫系統分享功能 (用於匯出/下載範例檔) |

## 🚀 建置與執行 (Build & Run)

### 環境需求
- **Flutter SDK**: 3.22.0 以上 (建議使用最新 Stable)
- **Dart SDK**: 3.0.0 以上
- **Android Studio**: 最新版

### 初次執行步驟
1. 確保專案路徑**不包含中文** (例如: `C:\Projects\meeting_app`)。
2. 開啟終端機，下載依賴：
   ```bash
   flutter pub get
   ```
3. 執行 App：
   ```bash
   flutter run
   ```

### 打包發布 (Release APK)
若要產生給他人安裝的檔案：
```bash
flutter build apk --release
```
產出的檔案位於：`build/app/outputs/flutter-apk/app-release.apk`

---
## 🐛 常見問題排除

- **Q: 匯入 CSV 失敗？**
    - A: 請確認檔案編碼為 UTF-8，且第一列包含「學號,姓名,身分」。
- **Q: 報錯 `Building with plugins requires symlink support`？**
    - A: 請在 Windows 設定中開啟「開發人員模式」。
- **Q: 報錯 `withOpacity` is deprecated?**
    - A: 請使用 `withValues(alpha: ...)`，這是 Flutter 3.27+ 的新 API，本專案已全面更新。