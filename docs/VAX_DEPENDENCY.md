# VAX 官方依賴與後端語言

2026-10-07：Pageforge Native 直接依賴官方 Go module，不維護第二份 VAX 協定。

## 來源與版本

- module：github.com/bnggbn/vax-action-history/go v0.0.2。
- 官方子 module tag：[go/v0.0.2](https://github.com/bnggbn/vax-action-history/tree/go/v0.0.2/go)，對應 commit 485baedacb74be255c0d3c726b8005ed63e39bab；上游修正分支 fix/jcs-utf8-order。Go Modules 直接使用此官方 tag，沒有另建 Native encoder。
- backend/go.mod 鎖版本，go.sum 驗證 module；無本地 replace、vendored copy、Node sidecar 或浮動 main 依賴。

先前 internal/vax/canonical.go 與 history.go 自行實作相容 vax-sdk 1.0.0 的 encoder／genesis／SAI，雖有 TypeScript golden fixture，但仍是第二份實作。本輪已移除，既有量測報告代表當時 runtime，不回填為官方 SDK 的效能數字。

## Pageforge 轉接層仍負責什麼

- Canonical 先把 Go struct／slice 轉成 JSON 值，再由官方 jcs.CanonicalizeValue 輸出；只有 Pageforge「安全整數」限制留在本地。排序、字串 escape 與編碼規則均遵循鎖定的 SDK。
- Genesis 與 SAI 分別呼叫官方 ComputeGenesisSAI／ComputeSAI；建立事件使用官方 sae.Envelope 型別。普通來源／正文 SHA-256 是儲存內容承諾，不是另一套 VAX 鏈演算法。
- Verifier 檢查 Pageforge 文件 ID、父版本、事件種類、時間、正文／筆記／投影雜湊、還原／採納來源及重複 ID。這是應用驗證，不複製 SDK 的通用 schema API 或協定實作。
- 正式事件仍承諾還原全文與 canonical 筆記；不把 storage root 當作全文 hash，也不改寫原始檔、ID、envelope 或 SAI。

既有 Pageforge 事件及筆記結構使用固定 ASCII 欄位名，中文／emoji 是值；保留 TypeScript 產生的歷史 golden fixture 驗證相容。任意新動態欄位名、數字型別或 SDK 升級須另做 byte-level 相容驗收，不能宣稱所有舊的任意 JSON 行為都一致。SDK 缺功能或協定修正應回官方 repo，再更新 release 依賴，不在 Native fork 補 encoder。

## 可選儲存附屬模組

2026-10-08：另依賴 github.com/bnggbn/vax-action-history/storage v0.1.0，位於同一官方 repo 的獨立 module；tag storage/v0.1.0，不更新核心 go/v0.0.0，也不發布 C／npm。原 internal/content 實作及 golden fixture 已移到上游。Native 直接使用 storage，無本地副本、replace 或提交的 workspace override。儲存 root 與 SAI／還原全文 hash 仍分開；[來源、錯誤映射與驗收](STORAGE_SDK.md)。

## 語言界線

後端自有程式的註解、診斷及 HTTP error 使用英文。fault code、HTTP status、errors.Is／errors.As 與 CAS 判斷不依訊息語言。

Flutter ApiException 將已知代碼轉成中文 message，保留英文 diagnostic。未知代碼／舊後端回應仍可讀，草稿衝突策略不變。詳細合約見 [API 錯誤](API_ERRORS.md)。INVALID_REQUEST 目前只有通用代碼，具體英文欄位診斷保留在 diagnostic；細分表單錯誤仍可後續增加代碼。

既有 evidence schema 的「全部線索」名稱屬於持久資料與驗證規則，本輪不換字串；Unicode golden／分塊／筆記測試樣本亦保留。官方 SDK 自身的中文註解由上游維護，沒有複製或改寫到 Native。

## 驗收

保留 TypeScript 歷史 fixture、Unicode canonical 與非法數字測試；跑 Go 全套測試／vet、Windows 後端編譯，Flutter 錯誤本地化／diagnostic／未知碼／舊回應／CAS 回歸與全套測試／analyze。這不是新一輪正式效能量測，也沒有修改正在執行的私人書庫。

本輪結果：Go 全套測試／vet 與 Windows 後端編譯通過；Flutter 全套 55 項測試通過、1 項 opt-in 探針跳過。修正測試字串插值 lint 後，錯誤合約 4 項測試與 analyze 再次通過。沒有重跑正式大檔效能探針，也沒有重建／替換正在執行的 Flutter release。

## 2026-10-12 第一版排序判斷（已更正）

以下保留 go/v0.0.1 的發布與驗收紀錄；當時以 TS 為準的方向錯誤，已由下節更正為原規格的 UTF-8 byte-order。

VAX 的專用 JCS 位於官方 go/pkg/vax/jcs，Native 之前已使用它。上游 go/v0.0.0 的 sort.Strings 依 UTF-8 bytes 排序，與 TS Object.keys(...).sort() 的 UTF-16 code units 不同；文件也把排序寫成 byte-order。已在官方 repo 改為 UTF-16 比較，保留 VAX 的 ASCII-only／非 ASCII escape／十進位規則，不換成通用 RFC 8785 encoder。

例：含「！」與「😀」的 key，canonical 應先出現 emoji。上游共享向量涵蓋高 BMP／補充平面邊界、相同 high surrogate、空 key／prefix 與巢狀陣列物件。原 Go 跨語言測試的 root 路徑錯誤並默默 skip；改成 module 內嵌向量一定執行，repo checkout 另核對共享檔案一致，發布後的 Go module 也能跑測試。

此修正會改變受影響動態 Unicode key 的 SAE／SAI；舊鏈須保留原始 SAE bytes 與 encoder 版本，或明確建立新鏈遷移，不能重算覆寫舊 hash。Pageforge 既有事件欄位及筆記欄位皆固定 ASCII，中文／emoji 作為值，歷史 fixture 按 bytes 保持相容。storage 仍鎖 v0.1.0，不更動 PFCO／PFCA 或正式全文承諾。未修改使用者 library。

上游本機驗證：Go1.23.12／1.26.2 全套測試與 vet 通過；pnpm 執行 TS 四套共116項測試及建置通過。這些是本機結果，未宣稱遠端 CI 已執行。Native 升版後：GOWORK=off、go mod tidy／verify、Go 全套測試／vet、從官方 tag 下載的核心 SDK 全套測試與 Windows 後端編譯均通過；ASCII-key TypeScript 歷史 fixture 與 Unicode key 轉接層回歸通過。正常預設 checksum 驗證成功，沒有提交或修改 replace／工作區覆寫／checksum 繞過設定。Dart 未修改，未重跑 Flutter 測試或重建／替換正在使用的 UI。

## 2026-10-12 UTF-8 byte-order 更正

依原始 byte-order 規格與 Go 參考實作地位，應修 TS 跟隨 Go，而非把 Go 改成 UTF-16 排序。官方 go/v0.0.2 的 jcs.go 與 go/v0.0.0 相同，TS 改為先將 key 編成 UTF-8，再比較 bytes；VAX 的 UTF-16 字串 escape 與排序是不同責任，保留原字串／數字編碼規則。例：key「！」排在「😀」之前。

上一版 go/v0.0.1 的 tag 不刪除／不覆寫；用它或舊 TS 建立的受影響 Unicode-key 鏈，仍須保留原 SAE bytes 與 encoder 版本，或明確遷移到新鏈，不能靜默重算 hash。Pageforge 既有 ASCII-key 事件、筆記與歷史 fixture 不受這兩次方向修正影響；storage 仍 v0.1.0。

上游驗收：Go1.23.12／1.26.2 全套測試與 vet、pnpm TS 四套共117項測試及建置通過。共享向量涵蓋 UTF-8／UTF-16 相反次序、BMP／補充平面、prefix／巢狀物件與像數字的 key；module 內嵌向量與共享檔案一致。Native 驗收：GOWORK=off，go mod tidy／verify、Go 全套測試／vet、官方 tag 下載版 SDK 全套測試、既有 TypeScript 歷史 fixture 與 UTF-8 key 轉接層回歸、Windows 後端編譯均通過。沒有 replace 或 checksum 繞過；未修改 Dart／私人 library、未替換執行中的 app。

局部驗證仍是提案，未以 proof 取代現有實體 bytes 驗證。[Pageforge 接法與界線](PARTIAL_VERIFICATION.md)。
