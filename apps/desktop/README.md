# Pageforge Windows client

原生 Flutter／Dart 介面，透過 repository 呼叫隨附的 Go 後端。

請從 repo 根目錄執行 `scripts/build.ps1 -RunChecks` 與 `scripts/dev.ps1`。
Windows 工作負載、設定路徑、支援格式與遷移進度以 [主 README](../../README.md) 為準。

- `lib/platform/`：Go 程序與啟動。
- `lib/data/`：資料模型及 HTTP repository。
- `lib/features/`：書架、閱讀、草稿、筆記與歷史。
- `lib/ui/`：主題。
- `test/`：隔離 repository 的 ViewModel 與 Widget 流程測試。

沒有檔案或 HTTP 邏輯直接寫入 Widget；草稿與閱讀進度分開管理。