# 官方 storage SDK 抽取

2026-10-08：Pageforge 內容儲存移入 VAX 官方 repo 的獨立 Go module。

## 來源與責任

- module：github.com/bnggbn/vax-action-history/storage v0.1.0；[版本來源](https://github.com/bnggbn/vax-action-history/tree/storage/v0.1.0/storage)。
- 上游工作分支 feature/storage-sdk；Go module tag storage/v0.1.0。核心保持 github.com/bnggbn/vax-action-history/go v0.0.0，不修改 canonical／genesis／SAI。storage 只用標準庫，最低 Go 1.23，不依賴核心、Pageforge、HTTP 或 internal 套件。
- 上游持有正文分塊、有序文本樹、opaque blob、catalog／散檔發布、有界 session、TextHash 與已驗依賴重驗，連同原 golden fixture 及單元測試。
- Native 的 internal/content 已移除；library 直接使用 storage.Ref／Store／Session，PutBlob／Blob 用於原筆記 JSON bytes。文件 ID、筆記 schema、VAX snapshot 比對、版本 CAS／容量投影與 API 保留在 Pageforge。
- 開發驗收使用未提交的 workspace override；最終 go.mod／go.sum 只依賴官方 tag，不保留本地 replace。

## 相容性

PFCO／PFCA magic、版本、kind 0／1／2、hash 輸入、UTF-8 分塊 policy、分支順序／長度、集合排序／編碼及散檔路徑不變。筆記 API 改名為 blob 不改寫原 payload，不加入 canonicalization，不遷移私人書庫。

抽取前以暫存 probe 同時執行原本地 writer 與上游 writer，對照空文、Unicode／CRLF、多區塊正文及 blob，覆蓋 catalog 與 loose 模式；所有 roots、邏輯長度及實體檔案 bytes 一致，golden fixture 檔案 hash 一致。Probe 在完成對照後移除；固定 golden／Unicode／容量／損壞回歸留在上游，Native 保留版本整合及錯誤合約回歸。

## 錯誤映射

| SDK Kind | Native API code |
| --- | --- |
| InvalidInput | INVALID_REQUEST |
| InvalidOptions／未知 Kind | INTERNAL_ERROR |
| LimitExceeded | LIMIT_EXCEEDED |
| Corrupt | STORAGE_CORRUPT |
| Missing | STORAGE_MISSING |
| IO | STORAGE_IO |
| UnsupportedFormat | UNSUPPORTED_STORAGE |
| UnsafePath | UNSAFE_PATH |

fault.CodeOf 用 errors.As 解讀 SDK 型別，既有外層 fault 優先；不以字串分類。SDK diagnostics 為英文，保留原 cause；Native HTTP 映射仍遮蔽私有檔案路徑，Flutter code／顯示與成功 payload 不變。

## 限制與發布

這是位置與依賴的重構，不是新增效能優化。PutText 仍掃全文、catalog 仍有重寫成本；root proof、範圍讀取、局部更新、GC／pack、差異復原、owner／衝突新鏈、程序鎖及 OAuth 未由本次 SDK 提供。storage Store／Session 不支援並行呼叫，writer ownership 由應用維持。對可信 root 的 bytes 驗證不等於對整鏈重寫的保護。

上游新增 Windows／Linux × Go 1.23／1.26 的唯讀 CI，只跑 tests／vet。未新增自動 GitHub release 或套件 registry 發布流程；storage tag 不觸發原 root vX.Y.Z 的 C／npm 發布。

## 本機驗收

已完成新舊 writer bytes／roots 對照；storage SDK 在 Windows Go 1.23.12 與 Go 1.26.2 的 tests／vet、原 VAX 核心 tests／vet、Native 暫存 workspace 的完整 tests／vet 通過。官方 tag 下載後，Native 在 GOWORK=off 下完整 tests／vet 與 Windows backend 建置亦通過；go mod verify 全部通過。Flutter 77 項通過、1 項既有 opt-in 探針跳過，analyze 無問題；本輪未更動 Dart 或重建／替換使用中的 Flutter 程式。新 Windows backend 真子程序完成 Unicode／CRLF 匯入、objects-v1 編輯、完整版本讀回、exit code 0 與正常釋鎖，僅使用隔離合成書庫。

上游 commit 333b2f1a3ebf840dca1d465dfbca9a10fe82b7e9 與 storage/v0.1.0 對應相同內容；[CI](https://github.com/bnggbn/vax-action-history/actions/runs/37756433770) 的 Windows／Linux × Go 1.23／1.26 四組 tests／vet 全通過。未量測新的效能數字，也未完成發布階段 crash／斷電驗收。

初次下載時，公開 Go checksum 服務仍快取發布前 unknown revision 的查詢。僅該自有 module 的一次 bootstrap 暫時設 GONOSUMDB 並以 GOPROXY=direct 取官方 Git tag，逐檔核對下載的 17 個檔案 SHA-256 與上游提交完全一致，再恢復預設 checksum／proxy 環境。go.sum 記錄版本與 h1，之後預設環境的下載／tidy／verify／tests／vet／build 通過；這不宣稱首次已取得 SumDB 簽名驗收。GONOSUMDB／GOPROXY 與 workspace override 均未寫入 repo 或全域設定。
