# 後端錯誤代碼合約

2026-10-06 已實作：Go 內容物件／版本轉接層使用 typed error；HTTP 統一回傳 code 與可讀 error；Flutter 書庫與外觀 repository 共用解析，草稿 CAS 依代碼判斷。此合約不改寫書庫、儲存 roots、VAX canonical bytes 或正式事件。

## HTTP 格式

```json
{
  "code": "STORAGE_MISSING",
  "error": "A required library file is missing. Check the files or backups."
}
```

Content-Type 為 application/json; charset=utf-8。保留原本的 error 字串並新增 code，成功 payload 不變。程式只依 code／HTTP status 分流，error 為英文公開診斷，Flutter 依 code 提供中文顯示文字並以 diagnostic 保存原訊息；不以 Error() 的英文或中文內容判斷。

| code | HTTP | 判斷與處理 |
| --- | --- | --- |
| INVALID_REQUEST | 400 | JSON、base64、文字格式或業務驗證無效；修正輸入 |
| UNSAFE_PATH | 400 | 路徑逃逸或不允許的連結；不繞過檔案邊界 |
| UNAUTHORIZED | 401 | token／Origin 驗證未通過 |
| FORBIDDEN | 403 | Host 不被允許 |
| NOT_FOUND | 404 | 要求的文件／路由不存在；文件目錄不存在與依賴缺失分開 |
| METHOD_NOT_ALLOWED | 405 | 路由存在但方法不符，保留 Allow 標頭 |
| CONFLICT | 409 | head、draft token、布局或外觀 revision 已更新；保留輸入 |
| LIMIT_EXCEEDED | 413 | 請求、文字、歷史、還原容量、物件數或樹深度超限 |
| STORAGE_MISSING | 500 | 已知書庫的原檔、版本、manifest 或必要物件缺失；不當作找不到文件 |
| STORAGE_CORRUPT | 500 | 必要 JSON 損壞、hash／型別／次序／長度不符、VAX 驗證失敗 |
| UNSUPPORTED_STORAGE | 500 | manifest 儲存標記、版本紀錄、catalog、物件版本／kind 不受支援 |
| STORAGE_IO | 500 | 讀寫、權限、Sync、rename 或 hard-link 發布失敗 |
| INTERNAL_ERROR | 500 | 內部容量配置、編碼或服務設定錯誤；未知 typed code 安全退回此類 |

物件缺失回 500，因為文件已存在而依賴不完整；只有未知資源使用 404。比過去「多數錯誤都回 400」更精確，舊客戶端仍能藉非 2xx 與 error 顯示失敗。部分尚未細分的既有業務驗證暫用 INVALID_REQUEST；新增跨 API 的錯誤應從來源給出 typed code。啟動／設定載入失敗與 transport timeout、斷線、回應超量不屬於成功收到的 HTTP JSON 錯誤回應，仍保留原本的本機錯誤型別。

## Go 與儲存邊界

- internal/fault 無 HTTP 依賴；New／Wrap／Ensure、CodeOf 與 Unwrap 保留代碼及原因，errors.Is／errors.As 仍可辨認原始檔案錯誤或衝突 sentinel。Ensure 不蓋掉來源已有的分類。
- Read 用於必要儲存依賴，缺檔為 STORAGE_MISSING，截斷／必要 JSON 解析失敗為 STORAGE_CORRUPT；Write 的發布／寫入失敗為 STORAGE_IO。
- 物件層區分格式、完整性與配置限制；版本轉接層把完整 VAX 驗證失敗歸為 STORAGE_CORRUPT。普通檔案格式、CAS 與可讀性驗證次序保持原規則。
- 可選 catalog、drafts、progress 與尚未建立的牆沿用原有缺檔規則；需要建立新物件時也能辨認「尚不存在」。包裝後使用 errors.Is(err, os.ErrNotExist)，不依 os.IsNotExist 對自訂 wrapper 的有限支援。
- internal/api/errors.go 集中 HTTP 映射與公開訊息；儲存／內部原因不把 OS 路徑、物件 hash 或底層診斷直接放進回應。原始 cause 保留給內部診斷，不寫出 token。驗證與 routing 404／405 也使用相同 JSON，成功回應不增加緩衝。

## Flutter 相容與衝突

ApiException 包含本地化 message、status、可選 code 及後端原文 diagnostic；保留二參數建構與原 library_repository.dart 的 export，既有呼叫仍可用。HttpLibraryRepository／HttpDesignRepository 共用 decodeResponse，非 JSON 錯誤回應、缺少或型別錯誤的欄位會回退可讀訊息，避免顯示 null 或另拋解析例外。

已知代碼在 Flutter 端翻譯；未知代碼及無代碼的舊回應使用原 error 文字，缺訊息時回退「後端請求失敗」。未知但有效的字串代碼會原樣保留。有代碼時 isConflict 只接受 CONFLICT；缺少有效代碼時才以舊後端的 409 相容處理。草稿 CAS 衝突另存副本並保留輸入；未知 coded 409 不自動建立副本或重試。這沒有實作正式正文／筆記／布局的「並行新鏈」，後續仍見 [ID 與同步合約](IDENTITY_SYNC.md)。

## 驗收與結論

Go 測試涵蓋包裝後 code／cause、物件超限／損壞／缺失、真實暖讀 API 的必要檔案缺失／JSON 損壞／VAX 失敗／不支援格式，以及驗證、404／405、請求超限與公開回應不帶本機路徑。Flutter 測試涵蓋兩個 HTTP repository、UTF-8 訊息、舊回應／非 JSON／壞欄位／未知代碼、coded／legacy 草稿衝突與未保存輸入保留。

abc5c7b 錯誤代碼階段：Go 全套測試、vet 與 Windows sidecar 編譯，Dart 格式、Flutter analyze 與 51 項測試均通過。最新 review 與大檔驗收見 [修正報告](experiments/REVIEW_FOLLOWUP.md)。既有長文 UI opt-in 探針未啟用；Windows symlink 權限限制仍沿用 [內容物件驗收](CONTENT_OBJECTS.md) 的未完成紀錄，不算已驗證。

本輪完成來源分類、HTTP 合約與前端傳遞，沒有新增自動修復、GC、重試或背景遷移。原有 [內容物件架構](CONTENT_OBJECTS.md) 與 [百萬字實測](experiments/CONTENT_OBJECTS.md) 的結論維持；實測仍對應原報告的 runtime commit，不把本輪回歸當成新的效能測量。分章／串流、局部樹更新、差異草稿復原、正式 root 事件、卡片發布及並行新鏈仍待實作。

2026-10-07 語言分工更新：後端自有診斷／公開 error 已改英文；Flutter 已知代碼中文化並保留 diagnostic，未知碼與舊回應沿用相容規則。Go 測試／vet／Windows 後端編譯、Flutter 55 項測試及 analyze 通過；[VAX 官方依賴與驗收範圍](VAX_DEPENDENCY.md)。
