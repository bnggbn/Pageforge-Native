# 內容物件與版本儲存架構

第一階段已實作新匯入書的正文樹、獨立筆記 blob、物件共用及版本讀寫。已有分節編輯與目前快照讀取；操作式後端、按章 API／可視區閱讀排版、差異復原、正式 VAX root 事件、衝突新鏈、卡片發布與舊書遷移仍待完成。

## 資料流與階段

```mermaid
flowchart TD
  Flutter["Flutter：閱讀／編輯／筆記"] --> Repository["Repository → Go API"]
  Repository --> Commands["版本命令：ID、基準、容量與 CAS"]
  Commands --> Revision["不可變版本紀錄：VAX envelope／SAI + 儲存 roots"]
  Revision --> Text["正文有序樹：子 hash 與 UTF-8 長度"]
  Revision --> Notes["獨立筆記 JSON blob"]
  Text --> Chunks["依內容分塊：16–64 KiB"]
  Chunks --> Objects["每書 SHA-256 物件：有界集合檔／大物件檔"]
  Notes --> Objects
  Objects --> Session["冷讀 session／暖讀已驗證依賴：重驗實際 bytes"]
  Session --> Adapter["逐版驗證正文／筆記雜湊，只還原所選快照"]
  Adapter --> Response["現有 reader API：目前全文 + 歷史摘要"]
  Response --> Flutter
  Repository -. 待實作 .-> Operations["有基準的文字操作／piece table"]
  Operations -.-> Recovery["草稿差異日誌與 checkpoint：不進正式 VAX"]
  Recovery -. 共用物件 .-> Objects
  Commands -. 待實作 .-> Chains["並行修改新鏈：forkedFrom + 各份 root"]
  Chains -. 共用物件 .-> Objects
```

實線是本階段接通的流程；虛線為後續。新資料的儲存 root 承諾物件內容、次序及長度，但正式 VAX 仍承諾還原後的全文／筆記 canonical hash；不能只驗物件 root 就宣稱完成正式 VAX 驗證。

## 實體格式與責任

```text
library/books/{documentId}/
  original.md 或 original.txt       原始 bytes，保持不可變
  manifest.json                    revisionStorage: objects-v1，版本 IDs／head
  versions/{revisionId}.json        storageVersion: 1，revision metadata + 兩個 root
  objects/catalog.pfca             有界二進位集合：typed hash → 原始物件 bytes
  objects/{hash前兩碼}/{hash}.pfo   大物件或集合滿時的 immutable 物件
  drafts/、progress.json            本階段維持原格式
  evidence-wall.json               現行 schema v2 布局，尚無布局 VAX
```

- content/objects.go：雜湊路徑、一般檔案／連結檢查、有界讀取、不可覆寫發布。
- content/tree.go：固定 writer policy 的 Gear 分塊、UTF-8 字元邊界、16 子項的有序樹建構；reader 不依賴切點演算法。
- content/catalog.go：有界二進位集合讀寫、單檔批次載入、溢出回退及先物件後版本的發布。
- content/session.go：物件 hash／型別／次序／長度驗證、共享依賴去重、正文還原及容量／深度限制。
- content/fingerprint.go：暖讀串流重驗已完成 session 的物件依賴，仍檢查實際 bytes。
- library/revision_objects.go：實體紀錄與原有 Revision 的轉接；布局只取 head 筆記，不讀正文樹。
- library/object_history.go：原檔／版本／物件 bytes 驗證、session 與快取邊界；完整歷史稽核另有 aggregate 還原預算。
- library/object_snapshot.go：一般 Load／Commit 只留所選正文／筆記與歷史摘要；舊版按需還原，不淘汰已驗 head。
- vax/history.go：逐版消費已驗內容的全文／canonical 筆記雜湊，保持原 envelope 與 SAI 協定。
- library/versions.go／import.go：既有命令與 CAS；先保存物件／版本，驗證可讀性與容量，再發布 manifest 或新書。

PFCO v1 bytes 是 ASCII PFCO + 版本 byte 1 + kind byte + payload。kind 0 為 UTF-8 正文葉，kind 1 為有序分支，kind 2 為筆記 JSON。物件 ID 是全部上述 bytes 的 SHA-256，型別與版本都在 hash 中，正文／筆記不能互換。

分支 payload 為一個子項數 byte（2–16），依序接每個子項的 32-byte hash 及 8-byte big-endian UTF-8 byte 長度。所有長度需與實際還原相符；不以檔名／mtime 代替內容驗證。空正文使用空葉，單葉即是 root。正文 chunk、樹節點與讀者段落 ID 不同；穩定章節／block ID 合約仍待實作。

PFCO v1 的 wire、物件 kind、hash、子項順序／長度、64 KiB 葉上限及 UTF-8 約束保持不變。reader 依既有節點讀取，不從正文重新推算切點；因此 writer policy 可以演進而不改寫舊 root。原 policy 使用低 15 bits，現用高 13 bits 的固定遮罩 8191 << 51、相同 Gear seed、16 KiB 下限及 64 KiB 上限，降低 CJK／emoji 尾端位元組造成的低位元偏差。新文可能得到不同 root；舊樹仍讀取且保留既有 VAX 全文雜湊。policy 不作 runtime 配置，不能宣稱切點均勻或每種文字都有固定共用比例。目前 PutText 接收全文、掃描所有字元並重新組織分支；相同物件不重寫。依內容切分降低文首插入造成的連鎖重切，並不保證所有輸入或惡意重複文字都能共用相同比例。

筆記目前是整份 notes JSON blob，修改筆記會重寫該 blob，但不重寫已共用的正文；按 noteId 的獨立樹、長筆記文本樹及個人 owner 分離仍待實作。布局、草稿與原始文件不因本階段被重新編碼。

## 發布、驗證與成本

小物件先放入有界集合，Flush 在同目錄寫暫存檔、Sync 再替換 catalog；保留所有已存在的 hash → bytes，不更換物件 ID。PFCA v1 為 ASCII PFCA + byte 1、4-byte big-endian 物件數，接按 hash 排序的條目；每條是 32-byte hash、4-byte big-endian wire 長度及完整 PFCO bytes。載入檢查實際容量、數量、重複 hash、物件 hash、截斷與尾端資料。集合是儲存索引，物件雜湊仍是內容依據。

大物件或集合滿時，物件先寫同目錄暫存檔並 Sync，再以 hard link 建立 hash 名稱，不能覆寫既有物件；已存在時驗證實際 hash 與 bytes，損壞時拒絕而非修補。先 Flush 集合／物件，再保存版本 JSON，最後切 manifest。集合／manifest 替換沿用同目錄 rename；Windows 的發布與斷電原子性尚未完整故障驗收，不宣稱跨平台斷電保證。Hard link 需要檔案系統支援；失敗回報並保留舊 head。

新書在暫存目錄內完整讀回驗證後才發布；objects-v1 與 legacy 正式 Commit 都在切 head 前驗證候選歷史的完整性與各自容量，超量不會新增一個下一次打不開的 head。失敗可能留下未被索引引用的物件或版本，尚無自動 GC；它們不進已發布歷史。Sync／原子發布不等於已完成斷電故障驗收，各發布階段 crash 與磁碟耗盡仍需另測。

每次讀書都驗證原始檔、版本紀錄與可達物件的實際 bytes，不跨操作信任 mtime。原始檔先串流雜湊；版本 metadata、文件資料／版本序列／儲存格式與原檔 hash 完全吻合已驗證快取時，使用該快取保存的依賴清單，串流重驗 loose 物件與 catalog 中的實際 wire bytes，省下樹解析與全文還原。Catalog 載入時仍驗全部條目，包含未被此 head 引用的物件；有界集合每次載入，沒有全程常駐。

冷讀 session 去重可達依賴、還原與驗 VAX 後，才建立依賴清單；不能拿未驗證 root 或 mtime 直接命中快取。缺物件、錯 hash、錯型別、換 root 後與 VAX 全文承諾不符都拒絕；不宣稱能防止含 head 的整鏈重寫。

一般 Go Load／Commit 及 reader HTTP 路徑在冷讀時仍完整驗證每個 VAX 事件，但不建立歷史全文陣列：每個不同正文 root 按葉順序串流計算全文 SHA-256，只暫存 root → digest；筆記 root 逐份 decode／canonical／雜湊後釋放，只有所選版本還原為正文 string 與 notes。Book 只帶該快照、History 摘要與 RevisionCount。還原窗口預算以單版正文／筆記估計，不加總每版展開全文。session 仍暫存去重後的可達物件 wire bytes，故還有 physical 歷史上限與物件數限制，不能說容量只取決於單版。

Go LoadHistory／CommitHistory 及未帶 view=reader 的舊 HTTP 介面保留完整歷史與 aggregate 還原上限；這是相容／稽核用途，不能當成新的一般 Load。legacy 底層仍完整解碼，按需介面只縮小回傳結果，未解決舊格式歷史容量與冷讀成本。

筆記仍是整份陣列 blob，第 N 版累加至 N 則時總量為 O(N²)；reader 釋放歷史 notes 解掉的是保留展開資料，沒有消除實體重複、逐版 canonical 成本或 physical 上限。下一階段需個別筆記物件與有序索引，仍以原 canonical notesHash 驗證，先不改正式 VAX 協定。

Catalog 每次新增物件時重寫有界集合；這避免許多小檔案開啟，但發布仍有集合寫入放大，尚非 append pack。正式提交仍完整驗證候選歷史，保存延遲未在本輪 benchmark 量測。後續 pack 索引／append／GC 須另外設計與故障驗收。

目前 API／草稿仍傳與存全文。Flutter 編輯已改為可配置的分節 TextField＋替換表，按鍵不 join 全文；同機百萬字 editor control 對照與選取界線見 [review 報告](experiments/REVIEW_FOLLOWUP.md)。閱讀器仍完整 Markdown 排版；按章 API／可視區排版、全文件操作模型與跨節編輯選取待補，不宣稱已完成百萬字整體驗收。

## 配置、相容與遷移

| 設定 | 預設 | 範圍與用途 |
| --- | --- | --- |
| storage.revisionFormat | objects-v1 | legacy 或 objects-v1；只決定新匯入書的格式 |
| storage.objectCount | 100000 | 1–1000000；一次歷史的可達物件及 catalog 條目上限 |
| storage.inlineObjectBytes | 65536 | 0–65536；新物件 payload 的集合門檻，0 停止新增集合條目；既有集合仍讀取 |
| storage.objectCatalogMiB | 8 | 1–32；catalog 實際位元組上限；滿時新物件存 loose 檔，縮小到低於現有大小會拒絕讀取 |
| storage.historyMiB | 256 | 原檔／版本 JSON／不同可達物件的讀取預算；另外限制還原內容與索引容量；集合緩衝另以 objectCatalogMiB 限制 |
| storage.recordMiB | 64 | 版本 metadata／manifest／草稿等 JSON 的單檔上限 |
| storage.verifiedCacheMiB | 64 | 一般新格式快取只計所選 head（包括當前章節／工作表投影）、版本 metadata／摘要及依賴描述；不計已釋放的整份 session payload；完整稽核仍計 aggregate；0 不建立新快取 |

單個正文葉上限 64 KiB，筆記 blob 沿用 limits.snapshotNotesMiB（預設 5），根正文的展開長度沿用 limits.textMiB（預設 5）。樹深度最多 32。容量估計與 Go TotalAlloc 均不是程序 RSS 的保證；檔案讀取、解碼與容器有額外成本。未引用 catalog 條目不計入可達歷史預算，避免失敗提交使舊 head 超量；集合整檔緩衝仍受獨立容量上限保護，實際讀取記憶體需另加此成本。objectCount 不限制未引用垃圾檔總數；GC 與實體磁碟總預算為後續工作。

舊書沒有 revisionStorage 欄位，繼續按 legacy 全文 JSON 讀寫，不改寫原版本、SAI 或備份。新書記錄格式後，即使全域改回 legacy，該書仍使用 objects-v1；新舊格式可同庫存在。既有來源去重仍生效，重新匯入完全相同原檔不會偷偷遷移舊書。舊 Web／舊 Native 不支援新物件格式；要給舊程式用，需未來顯式匯出完整 legacy 書庫，不能只刪 marker 或切設定降版。

後續舊書 migration 須另外建立新索引、逐版還原／VAX 比對、保留原始檔及回滾備份；本輪沒有對私人書庫做批次轉換。只有原有 ID 與 legacy SAI 被保留；新的 root 型正式事件、owner／cardInstanceId／新鏈及發布事件沿用各自待實作合約。

reading.editorSectionUnits 控制 Flutter 初始編輯節的 UTF-16 大小：預設16000，1000–65536；和儲存 UTF-8 chunk 不同。停筆草稿仍保存全文，不增加正式 VAX 節點。

## 錯誤回應

物件／版本轉接層已使用 typed code：缺失依賴、完整性失敗、容量限制、未知格式、路徑限制及讀寫失敗各自分類；API 保留可讀 error 並新增 code。必要物件缺失不當作文件 404，底層原因仍可 errors.Is／errors.As 辨認，公開訊息不帶本機路徑。暖讀驗證與候選發布失敗沿用同一合約，格式／VAX hash 不變；[完整代碼與相容規則](API_ERRORS.md)。

## 驗收

測試覆蓋精確 Unicode／換行往返、依內容分塊的文首插入共用、重送同內容不增加物件、正文／筆記型別隔離、有序子項與錯長度、空正文、容量／物件數、錯 hash／缺依賴／mtime 恢復、root 置換與 VAX 不符、原檔及版本不被改寫、還原共用、筆記切片隔離、布局只取筆記、新設定不改舊書、改設定後仍讀新書，以及超量發布失敗仍保留舊 head。

另涵蓋二進位集合截斷、錯長度、重複 hash、超量 count、尾端垃圾、集合容量滿後回退 loose、停用新集合寫入後仍讀既有集合。

新增縮小容量的 distinct-edit／accumulating-note 兩道牆回歸：LoadHistory 超量時，一般 Load／Commit 仍能開書、保存、取舊版與還原；暖讀與歷史查看保留 head 快取，外部修改仍拒絕。另覆蓋 legacy 超量提交不切 manifest，以及 ASCII／CJK／emoji 的新舊切法往返與插入共用。

Go HTTP 測試使用預設的新匯入格式；原 Web golden fixture、舊儲存回歸及既有長文診斷探針明確保持 legacy，避免混淆原基準。相同文本／40 版的效能對照使用 BenchmarkObjectHistory，結果見 [物件儲存基準](experiments/CONTENT_OBJECTS.md)。


前一輪 abc5c7b 驗收：Go 全套測試及 vet、Go Windows sidecar 編譯、Dart 格式檢查（0 修改）、Flutter analyze 均通過；Flutter 51 項測試通過（含錯誤代碼回歸），1 項需 opt-in 的長文 UI 探針未啟用。Windows 連結目錄回歸因環境無建立 symlink 權限而跳過，尚須在支援環境補驗；不能把此項算成已驗收。失敗超量提交後，未引用集合內容不影響舊 head 的冷／暖讀取，另有回歸測試。
