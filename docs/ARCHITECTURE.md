# 原生架構

```text
apps/desktop/lib/
  platform/                  Go 程序啟動與生命週期
  data/                      immutable 畫面模型、HTTP repository 合約
  features/library/          書架 ViewModel 與介面
  features/reader/           閱讀協調、working copy、reading position
  features/reader/views/     文字／PDF／表格、編輯、筆記、歷史畫面
  features/design/           外觀資料、已保存外觀、工作室與共享預覽
  features/history/          diff 請求與過期結果隔離
  ui/                        主題與共用介面
backend/
  cmd/pageforge/             啟動、訊號與父程序管線
  internal/config/           共用設定與本機覆寫
  internal/model/            library 相容的資料模型
  internal/library/          檔案邊界、匯入、版本、草稿與進度
  internal/vax/              vax-sdk 1.0.0 的 canonical bytes 與 SHA-256 協定
  internal/design/           嚴格外觀 JSON、revision 衝突檢查與原子保存
  internal/compare/          有輸入上限與 deadline 的文字 diff
  internal/api/              本機 API 與請求驗證
```

Widget 不直接操作 library。ViewModel 依赖 repository 合約，Go 的儲存與 VAX 分開。
working copy 與 reading position 各自控制防抖與落盤；筆記輸入不通知整個閱讀畫面重新解析 Markdown。
表格使用固定列高的 ListView.builder，只建立可見列；完整內容另開選取視窗。

桌面程序啟動 Go sidecar，Go 監聽 127.0.0.1 的動態 port。
隨機 256-bit token 經 stdout 管線提供 Dart，每個 API 請求帶 Bearer token。
token 不放 argv、設定或日誌；拒絕 browser Origin 與非 loopback Host，不開 CORS。
父程序 stdin 關閉時，Go 停止服務並釋放 library 鎖。

library 使用既有 `server.lock` 排他檔，避免 Web 與原生版同時写同一書架。
文件原始檔保持不可覆寫，版本節點先保存，再切換 manifest。
草稿有基準 revision ID 與版本 token；過期寫入不覆蓋另一份草稿。
進度寫入獨立 progress.json，文字修改的 epoch 使舊位置失效。

VAX 依實際 vax-sdk 1.0.0 原始碼實作：UTF-16 非 ASCII escape、排序與兩階段 SHA-256。
Pageforge envelope 的數值只允許安全整數 timestamp；未知浮點 envelope 拒絕。
此階段每次載入與提交完整驗證，尚未導入快取或歷史分頁。
驗證沒有簽章／外部可信 head，不提供對整鏈重寫或尾端截斷的保護。

測試使用隔離暫存 library，包含現有 TypeScript SDK 產生的中文／emoji golden fixture。
不讀取或寫入使用者的私人書籍。
