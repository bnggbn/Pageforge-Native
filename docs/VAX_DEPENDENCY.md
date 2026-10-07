# VAX 官方依賴與後端語言

2026-10-07：Pageforge Native 直接依賴官方 Go module，不維護第二份 VAX 協定。

## 來源與版本

- module：github.com/bnggbn/vax-action-history/go v0.0.0。
- 官方子 module tag：[go/v0.0.0](https://github.com/bnggbn/vax-action-history/tree/go/v0.0.0/go)，對應 commit 0645a869fd06f213d4cb09eeceaa05bf7da5e612；同 commit 的 [release v0.0.0](https://github.com/bnggbn/vax-action-history/releases/tag/v0.0.0)。
- backend/go.mod 鎖版本，go.sum 驗證 module；無本地 replace、vendored copy、Node sidecar 或浮動 main 依賴。

先前 internal/vax/canonical.go 與 history.go 自行實作相容 vax-sdk 1.0.0 的 encoder／genesis／SAI，雖有 TypeScript golden fixture，但仍是第二份實作。本輪已移除，既有量測報告代表當時 runtime，不回填為官方 SDK 的效能數字。

## Pageforge 轉接層仍負責什麼

- Canonical 先把 Go struct／slice 轉成 JSON 值，再由官方 jcs.CanonicalizeValue 輸出；只有 Pageforge「安全整數」限制留在本地。排序、字串 escape 與編碼規則均遵循鎖定的 SDK。
- Genesis 與 SAI 分別呼叫官方 ComputeGenesisSAI／ComputeSAI；建立事件使用官方 sae.Envelope 型別。普通來源／正文 SHA-256 是儲存內容承諾，不是另一套 VAX 鏈演算法。
- Verifier 檢查 Pageforge 文件 ID、父版本、事件種類、時間、正文／筆記／投影雜湊、還原／採納來源及重複 ID。這是應用驗證，不複製 SDK 的通用 schema API 或協定實作。
- 正式事件仍承諾還原全文與 canonical 筆記；不把 storage root 當作全文 hash，也不改寫原始檔、ID、envelope 或 SAI。

既有 Pageforge 事件及筆記結構使用固定 ASCII 欄位名，中文／emoji 是值；保留 TypeScript 產生的歷史 golden fixture 驗證相容。任意新動態欄位名、數字型別或 SDK 升級須另做 byte-level 相容驗收，不能宣稱所有舊的任意 JSON 行為都一致。SDK 缺功能或協定修正應回官方 repo，再更新 release 依賴，不在 Native fork 補 encoder。

## 語言界線

後端自有程式的註解、診斷及 HTTP error 使用英文。fault code、HTTP status、errors.Is／errors.As 與 CAS 判斷不依訊息語言。

Flutter ApiException 將已知代碼轉成中文 message，保留英文 diagnostic。未知代碼／舊後端回應仍可讀，草稿衝突策略不變。詳細合約見 [API 錯誤](API_ERRORS.md)。INVALID_REQUEST 目前只有通用代碼，具體英文欄位診斷保留在 diagnostic；細分表單錯誤仍可後續增加代碼。

既有 evidence schema 的「全部線索」名稱屬於持久資料與驗證規則，本輪不換字串；Unicode golden／分塊／筆記測試樣本亦保留。官方 SDK 自身的中文註解由上游維護，沒有複製或改寫到 Native。

## 驗收

保留 TypeScript 歷史 fixture、Unicode canonical 與非法數字測試；跑 Go 全套測試／vet、Windows 後端編譯，Flutter 錯誤本地化／diagnostic／未知碼／舊回應／CAS 回歸與全套測試／analyze。這不是新一輪正式效能量測，也沒有修改正在執行的私人書庫。

本輪結果：Go 全套測試／vet 與 Windows 後端編譯通過；Flutter 全套 55 項測試通過、1 項 opt-in 探針跳過。修正測試字串插值 lint 後，錯誤合約 4 項測試與 analyze 再次通過。沒有重跑正式大檔效能探針，也沒有重建／替換正在執行的 Flutter release。
