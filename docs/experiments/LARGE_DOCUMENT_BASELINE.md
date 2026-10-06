# 大型文件現況基準：2026-10-06

實驗分支 experiment/large-document-baseline；產品基準 bfb57bd。分支只加入 opt-in 探針、腳本與本報告，未更換儲存 schema、提高正式容量或加入 Merkle 套件。原始數據見 [JSON](large-document-baseline.json)。這是現有實作的診斷基準，不代表通過百萬字平台驗收。

## 環境與方法

- Windows build 26200、amd64、22 個邏輯處理器；Go 1.26.2、Flutter 3.41.7／Dart 3.11.5。
- 使用固定種子的中英文字、數字、emoji 與每 160 字元的段落分隔；大小為 Unicode rune 數。Go／Dart PRNG 不同，兩端測試文字不逐字相同。沒有圖片、複雜 Markdown、EPUB 或跨書籍資料，不能代表全部文件形狀或壓縮收益。
- Go 每個 case 使用測試臨時書庫。先驗證有效預設的 5 MiB 文字限制；再只在測試 Store 配置中設 text／document 32 MiB、request 64 MiB、history 512 MiB，保留 record／cache 64 MiB。正常產品設定與真實書庫不變。
- 合成多版 fixture 直接寫入有效 VAX revision，避免準備資料時逐版 Commit 的平方成本；正式量測 edit／note 保存使用 public Commit。正文每版僅增加短字尾，未刻意製造大幅修改。
- Go 冷讀取關閉／重開 Store 清除應用程式快取；沒有清除 Windows 檔案快取。每次量測前 GC，cold／repeat／reader／draft／edit 各取 3 次，表內為中位數。draft 使用 CAS 重寫同一草稿；edit 連續增加 3 版，因此各次的歷史長度不同。note／import／diff 僅量 1 次。
- allocatedBytes 是 Go TotalAlloc 的累計差，不是峰值記憶體、留存 heap 或 RSS。reader_handler 包含真實 handler 的讀取與 JSON 序列化，但使用 httptest recorder，沒有網路傳輸與 Dart 解碼。磁碟大小是檔案邏輯 bytes，不是 NTFS 實際配置或壓縮後容量。
- Flutter 使用實際 EditorView／TextDocumentView、1200 × 900 widget-test engine 與 FakeRepository，資料準備與 model.load 不計入首個 pump。編輯量測以 controller 更新及 onChanged 模擬追加一字，做 5 次；不包含實體鍵盤、IME、HTTP、native release FPS 或 GPU／RSS profiling。idle 指下一次 pump；jump 指跳到末尾後的 pump。
- 六組 UI 案例序列執行。Go 首輪較小案例與另一份 10 萬字 editor 探針有短暫重疊；此處 UI 數據取其後的序列測試，Go 較大案例沒有該 UI 探針競爭。系統背景工作仍會影響時間，小樣本不據此宣稱固定加速倍數。

## Go 讀取結果

| 字元數 | 初始版本數 | 正文 MiB | 可放入驗證快取 | 冷讀取 ms | 重複讀取 ms | 重複讀取累計配置 MiB |
| --- | --- | --- | --- | --- | --- | --- |
| 100,000 | 10 | 0.17 | 是 | 81.07 | 19.21 | 0.08 |
| 1,000,000 | 10 | 1.71 | 是 | 242.63 | 48.19 | 0.08 |
| 3,000,000 | 1 | 5.13 | 是 | 86.67 | 16.34 | 0.06 |
| 3,000,000 | 10 | 5.13 | 是 | 1160.80 | 113.93 | 0.08 |
| 3,000,000 | 40 | 5.13 | 否 | 4186.17 | 4319.22 | 1059.13 |
| 5,000,000 | 1 | 8.55 | 是 | 136.96 | 29.11 | 0.06 |
| 5,000,000 | 10 | 8.55 | 否 | 1015.71 | 1014.83 | 488.81 |

300 萬字 × 40 版的 original + versions 約 211.79 MiB，超過 64 MiB 快取門檻；重複載入依然完整解碼／驗證，每次累計配置約 1.03 GiB。reader 回應雖只約 5.17 MiB，後端歷史成本仍存在。500 萬字 × 10 版也超過快取門檻。

300 萬字 × 40 版完成 3 次 edit、1 次 note 及同一份草稿保存後，文件目錄約 237.62 MiB。筆記提交仍重複保存正文；此結果不把新增版本的成本誤算成只改幾個 bytes 的差異儲存。

## Flutter 結果

| 字元數 | View | 首次 pump ms | idle pump ms | 追加一字 pump ms（中位數） | 跳末尾 pump ms |
| --- | --- | --- | --- | --- | --- |
| 100,000 | editor | 856.31 | 14.23 | 423.88 | — |
| 100,000 | plain | 1150.49 | 100.24 | — | 51.77 |
| 100,000 | markdown | 1515.57 | 61.75 | — | 58.95 |
| 1,000,000 | editor | 6069.68 | 22.65 | 7581.39 | — |
| 1,000,000 | plain | 12277.69 | 1164.39 | — | 732.65 |
| 1,000,000 | markdown | 13639.44 | 414.95 | — | 333.86 |

百萬字 editor 的追加排版約 7.58 秒，plain／markdown 首次建立約 12.28／13.64 秒。這顯示目前整文編輯與全量閱讀排版是獨立瓶頸；即使儲存 root 很便宜，也不會自動改善 UI。測試通過表示此次診斷能完成且未拋出 framework exception，不表示體驗可用。

## 容量與 diff

100 萬字的混合正文約 1.71 MiB，可通過預設文字限制；300／500 萬字約 5.13／8.55 MiB，被預設拒絕。這與 300 萬個一般中文字約 8.58 MiB 的算術並不矛盾，因為此測試含大量 ASCII。

100 萬字及以上的前後兩份文本總 UTF-16 長度超過現有 diff 上限，拒絕比較。500 萬字在拒絕前仍配置約 66.10 MiB，來源為目前建立 rune／UTF-16 中間切片後才檢查長度。後續應用串流／提早停止的長度檢查，而非放寬全文 diff 上限。

## 依據這次結果的順序

1. 保持現有容量保護。先完成獨立草稿最大等待／合併排程，避免持續輸入完全不落盤。
2. 建立文件操作模型，避免按鍵就產生整文複製／排版；閱讀按可視區排版，跨段落／全文選取由邏輯文件範圍維持。
3. 分塊物件、正文／筆記共用、局部更新與可驗證復原；正式 VAX root 事件合約另外遷移。與本分支同樣案例比較，不只測 root 計算。
4. 冷歷史驗證／按需讀取、diff 邊界檢查與分段比較；最後補 Windows release 的鍵盤／IME、幀時間、峰值記憶體、crash 注入及更大資料形狀，再放寬容量。

## 重跑

在 repo 根目錄執行 scripts/probe-large-documents.ps1（Go／Flutter 在 PATH）；可用 -GoPath／-FlutterPath 指定 SDK，-SkipUI 或 -SkipBackend 分開執行，-UICharacters 與 -Views 選案例。結果寫入獨立的 .preview/large-document-日期時間，不覆蓋既有報告。Go 測試臨時書庫會由 testing 清理，Flutter repository 全部為記憶體假資料。

一般 go test／flutter test 跳過大型探針；明確設定 PAGEFORGE_LONG_DOCUMENT_PROBE 才執行。腳本依序跑 Go 和 UI；UI 每一案例開獨立程序，避免同時保留多個大畫面。未量測的 300／500 萬字 UI、Windows release、p95／峰值記憶體、實際傳輸、100 版歷史與故障注入仍列為後續驗收，不能以本報告取代。
