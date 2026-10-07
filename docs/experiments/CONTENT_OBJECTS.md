# 內容物件儲存效能實測

> 2026-10-07 補充：本報告保留原提交／工作負載及歷史數據。原 objects benchmark 的 notes 情境是反覆更新同一則筆記，沒有涵蓋持續累加；新增負載、目前快照讀取與 UI 優先順序見 [review 修正報告](REVIEW_FOLLOWUP.md)。


2026-10-06，Windows amd64、Intel Core Ultra 7 165H、Go 1.26.2。比較同一份合成文本與 40 個有效 VAX 版本的 legacy／objects-v1。原始逐項結果見 [JSON](content-objects-results.json)，架構與限制見 [內容物件合約](../CONTENT_OBJECTS.md)。這是本次 objects-v1 實作的測量，並非既有 legacy 基準的追溯修改。

量測對應 runtime commit `66d3095`，後續 commit 只補架構與實測文件。

## 方法

使用 BenchmarkObjectHistory（backend/internal/library/object_history_bench_test.go），固定 seed 526、100 萬 rune；ASCII、中文、emoji、空行混合，正文約 1.375 MiB UTF-8。不是 100 萬個純中文字。每書 40 版，兩種形狀：

- 筆記變更：同一正文、39 次同 noteId 的筆記變更。
- 文首小改：39 個各有不同短前綴的正文版本；前綴不是累積插入。

資料只用隔離暫存書庫。測量前直接建立有效版本，排除一般 Commit 逐次驗證歷史的準備時間；不代表正式保存延遲。兩種格式皆實際經過 Load 與 VAX 驗證，完全相同正文 hash 共用的優化也套用到 legacy，避免以舊驗證器作不公平比較。

冷測量每次清空 Go 應用程式的驗證快取，沒有清 Windows 檔案快取；重複測量先完成一次 Load。每個子項 3 次，表內時間為 Go benchmark 平均值，不是 median／p95；未和 Flutter 建置同時執行。命令：

```powershell
go test ./internal/library -run '^$' -bench '^BenchmarkObjectHistory$' -benchtime=3x -benchmem
```

objects-v1 使用預設 64 KiB inline 門檻、8 MiB 二進位 catalog、10 萬物件、256 MiB history 與 64 MiB 驗證快取。磁碟計入原檔、manifest、全部版本及物件／catalog 的邏輯檔案大小，不是 NTFS 實際配置大小。B/op 是一次讀取的 Go 累計配置，非峰值記憶體／RSS；未量 HTTP 傳輸、Dart JSON、Flutter 全文排版與輸入。

## 結果

| 形狀 | 格式 | 讀取 | ms／次 | 磁碟 MiB | 累計配置 MiB／次 | 配置次數／次 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 筆記變更 | legacy | 冷 | 1081.01 | 56.370 | 238.589 | 24054 |
| 筆記變更 | legacy | 重複 | 161.47 | 56.370 | 0.137 | 729 |
| 筆記變更 | objects-v1 | 冷 | 118.91 | 2.750 | 11.630 | 23799 |
| 筆記變更 | objects-v1 | 重複 | 90.23 | 2.750 | 1.787 | 2167 |
| 文首小改 | legacy | 冷 | 1126.06 | 56.370 | 291.218 | 21339 |
| 文首小改 | legacy | 重複 | 171.69 | 56.370 | 0.141 | 691 |
| 文首小改 | objects-v1 | 冷 | 245.70 | 4.889 | 121.421 | 23337 |
| 文首小改 | objects-v1 | 重複 | 101.27 | 4.889 | 3.974 | 2605 |

同文筆記書庫減少約 95.1% 邏輯儲存，文首小改減少約 91.3%。這輪兩種形狀的冷讀與重複讀均改善，但暖讀配置高於 legacy：二進位 catalog 每次載入，避免小檔案 I/O 所換取的有界緩衝成本。結果有 Windows I/O 與背景掃描變異，不宣稱固定加速倍數或所有文件形狀都同樣改善。

## 還有的成本

- 首次讀取仍還原每個不同正文 root 的完整 string；40 份稍異文本仍有版本數 × 正文大小的還原配置。超量明確拒絕，尚無按章／單版 VAX root 協定。
- 新版保存仍掃描提交的全文、重建有序分支、重寫有界 catalog 並驗證候選歷史；不是局部樹更新的 O(log n) 保存。
- 暖讀仍重驗原檔、版本紀錄及實際物件 bytes。Catalog 上限後使用 loose 物件，更多小檔案可能影響暖讀，需要 append pack／索引與更長歷史的另一次實測。
- 現有私人書庫未遷移。Flutter 全文輸入瓶頸、定時差異復原、卡片發布及並行新鏈功能尚未完成。

## 原始 benchmark 輸出

```text
goos: windows
goarch: amd64
pkg: github.com/bnggbn/Pageforge-Native/backend/internal/library
cpu: Intel(R) Core(TM) Ultra 7 165H
BenchmarkObjectHistory/notes/legacy/cold-22    	       3	1081011333 ns/op	        56.37 disk-MiB	250178925 B/op	   24054 allocs/op
BenchmarkObjectHistory/notes/legacy/repeat-22  	       3	 161465533 ns/op	        56.37 disk-MiB	  144074 B/op	     729 allocs/op
BenchmarkObjectHistory/notes/objects-v1/cold-22         	       3	 118907000 ns/op	         2.750 disk-MiB	12194866 B/op	   23799 allocs/op
BenchmarkObjectHistory/notes/objects-v1/repeat-22       	       3	  90227800 ns/op	         2.750 disk-MiB	 1873568 B/op	    2167 allocs/op
BenchmarkObjectHistory/prefix_edits/legacy/cold-22      	       3	1126056400 ns/op	        56.37 disk-MiB	305364157 B/op	   21339 allocs/op
BenchmarkObjectHistory/prefix_edits/legacy/repeat-22    	       3	 171690767 ns/op	        56.37 disk-MiB	  148080 B/op	     691 allocs/op
BenchmarkObjectHistory/prefix_edits/objects-v1/cold-22  	       3	 245703667 ns/op	         4.889 disk-MiB	127318858 B/op	   23337 allocs/op
BenchmarkObjectHistory/prefix_edits/objects-v1/repeat-22         	       3	 101271667 ns/op	         4.889 disk-MiB	 4167077 B/op	    2605 allocs/op
PASS
ok  	github.com/bnggbn/Pageforge-Native/backend/internal/library	25.603s
```
