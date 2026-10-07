# 大文件 review 修正與優先順序（2026-10-07）

## 結論

前一輪物件儲存減少正文重複，但 benchmark 反覆修改同一則筆記，不能代表持續累加。磁碟去重不等於記憶體去重，也不等於 UI 排版改善。本輪一般 Go Load／Commit 的 objects-v1 Book 只帶目前快照與歷史摘要；正文按葉串流雜湊，筆記逐份驗證釋放。LoadHistory／CommitHistory 明確保留完整歷史相容／稽核介面與 aggregate 上限，未帶 view=reader 的 HTTP 合約也保持相容。

完整性沒有降成只信 root／mtime：每次仍重查原始檔、版本與全部可達物件 bytes。暖快取留 head、已驗 metadata 及依賴描述；查看舊版按需還原，不淘汰 head。cache 門檻不再按所有展開版本計算，但暖讀仍隨歷史記錄與可達 bytes 增長。冷讀 session 仍暫存 physical payload，實體歷史總預算不能取消；這不是只有單版大小的無限歷史。

## 使用者提供的 Linux 量測

以下為使用者提供，未取得原三個 review 探針，未宣稱 Windows 原樣重現。Linux 容器、Go 1.24.7 scratch go.mod、合成文字；Flutter 沒有執行。相同情境為 import + 1 edit + 30 則累加筆記，共 32 版。

| 情境 | 100 萬字 legacy | 100 萬字 objects-v1 | 170 萬字 legacy | 170 萬字 objects-v1 |
| --- | --- | --- | --- | --- |
| 第 30 則筆記 commit | 1.72 s | 211 ms | 3.15 s | 413 ms |
| 開書 | 1.77 s | 30 ms | 3.07 s | 52 ms |
| 邏輯磁碟 | 99.0 MiB | 9.1 MiB | 168 MiB | 15.0 MiB |
| 匯入 | 73 ms | 165 ms | 92 ms | 323 ms |
| 首次 edit commit | 76 ms | 223 ms | 100 ms | 343 ms |

另有 93 萬字、每版在不同位置改一句，80–90 版間拒讀；100k 字、100 字引文＋60 字內文持續累加，500–600 則間拒讀。前者是保留所有展開正文，後者同時有 O(N²) notes blob 與展開筆記。這些是原分支／原 Load 合約的結果，不能直接套用現在的新讀取路徑。

待取得 review_measure_test.go、review_walls_test.go、review_cut_test.go 後再原樣重跑；本輪另有自己的縮小容量回歸與 Windows probe，不混作相同資料。

## 本輪後端驗收

- object_snapshot_test.go：4 MiB 歷史、1 MiB cache，100k-rune source、48 次不同位置 edit 或48則持續累加 notes。LoadHistory 超量時，一般 Load 可開書且只帶一版／49則摘要，cache 留 head；舊版、還原與續存可用。這是容量語意回歸，不是使用者 80／600 版探針的原樣重跑。
- legacy_preflight_test.go：既有全文書達到容量時，保存失敗不切換 manifest，舊 head 冷讀仍可開；既已超量書尚未自動修復。
- reader_snapshot_bench_test.go：1M mixed runes、100 版，不同位置修改／持續新增筆記，冷暖讀與配置量；直接建立有效版本，準備時間不計，沒有測正常 Commit 延遲。
- chunk_policy_test.go：固定 seed526、700k runes，ASCII、中文、12種emoji；舊低15bits 與新高13bits 的樹均可精確還原，文首插入不連鎖重寫整文。測量為合成資料，不保證其他文字分布。

writer 使用高13bits 的固定遮罩 8191 << 51；只降低低位元遮罩對狹窄 emoji 字母表仍無效。新舊 PFCO v1 wire／讀取約束不變，不重新切舊樹或修改正式 VAX。實際 hard-limit 葉比例：ASCII 6/14 → 0/30，中文19/43 → 8/56，emoji41/42 → 9/67。

一般 Load／Commit 的一份快照回傳合約亦對 legacy 做回歸，底層全解碼限制仍保留。cache／reader 預算包含當前章節與工作表投影；另有超過 cache 容量的投影不常駐及可變 slice 隔離測試。

## 本機 Go 對照量測

量測 runtime 為 ed5f7d3；後續 legacy 回傳與當前投影預算回歸不追溯改寫數值。Windows amd64、Core Ultra 7 165H、Go1.26.2，一書100版，1M mixed runes（benchmarkObjectText／seed526），每個子項3次的平均。cold 只清應用程式 cache，不清 OS cache；warm 先完成一次一般 Load。B/op 是累計配置量，不是峰值或RSS；沒有 HTTP／Flutter／正常 Commit 時間。原始數值見 [JSON](review-followup-results.json)。

| 工作負載／模式 | Load 平均 | 配置／次 | allocs／次 |
| --- | --- | --- | --- |
| distinct_edits / cold | 383.3 ms | 22.11 MiB | 56039 |
| distinct_edits / warm | 251.4 ms | 5.91 MiB | 5861 |
| accumulating_notes / cold | 429.7 ms | 46.45 MiB | 342671 |
| accumulating_notes / warm | 317.8 ms | 3.67 MiB | 4656 |

這組結果顯示一般讀取不再為100份正文配置全文 string；暖讀仍重驗歷史 bytes，不能稱與歷史長度無關，也不能和使用者 Linux 32版數字直接比快慢。

在 backend/ 重跑：

```powershell
go test ./internal/library -run '^

1. UI 可視區閱讀排版與按章 API 優先；必須驗收 Markdown／TXT／EPUB 跨段落、畫面外全文選取、複製、重複段落筆記及閱讀進度。不能用互不相通的 SelectionArea 假裝完成。
2. 筆記逐條物件與有序索引：現有整陣列 blob 仍 O(N²)，session／磁碟／冷 canonical 成本仍隨累加歷史成長；之後仍可能撞 physical 上限。
3. 舊書顯式遷移與超量書出路；legacy 已有發布預檢，底層仍全文解碼。
4. server.lock 殘留與單本壞 manifest 拖垮書架：仍未修正。正常容量失敗不切 head，不能把它當成這兩項修復。
5. 持續輸入最大保存等待、可驗證差異復原與 crash 注入；目前仍停筆防抖保存完整草稿。
6. catalog 整檔改寫、正式提交前後歷史驗證、局部樹更新／正式 root 型事件：先按實際收益排程，不搶在 UI 體驗之前。

本輪完整驗收結果與 UI 對照將隨實際完成更新；不把歷史基準或外部 review 算成本次已重現。
 -bench '^BenchmarkReaderSnapshotWorkloads

1. UI 可視區閱讀排版與按章 API 優先；必須驗收 Markdown／TXT／EPUB 跨段落、畫面外全文選取、複製、重複段落筆記及閱讀進度。不能用互不相通的 SelectionArea 假裝完成。
2. 筆記逐條物件與有序索引：現有整陣列 blob 仍 O(N²)，session／磁碟／冷 canonical 成本仍隨累加歷史成長；之後仍可能撞 physical 上限。
3. 舊書顯式遷移與超量書出路；legacy 已有發布預檢，底層仍全文解碼。
4. server.lock 殘留與單本壞 manifest 拖垮書架：仍未修正。正常容量失敗不切 head，不能把它當成這兩項修復。
5. 持續輸入最大保存等待、可驗證差異復原與 crash 注入；目前仍停筆防抖保存完整草稿。
6. catalog 整檔改寫、正式提交前後歷史驗證、局部樹更新／正式 root 型事件：先按實際收益排程，不搶在 UI 體驗之前。

本輪完整驗收結果與 UI 對照將隨實際完成更新；不把歷史基準或外部 review 算成本次已重現。
 -benchtime=3x -benchmem
```

Go 全套測試、vet 與 Windows sidecar 編譯通過；新程式編譯到忽略的預覽目錄，沒有替換／重啟正在使用的 app。一次早期全套測試遇到 Windows catalog rename 的 Access is denied；原因未確定，隔離及後續全套重跑皆通過。失敗保持舊 head 的預檢已有回歸，但本輪未完成 Windows 各發布階段的 crash／共享檔案故障注入，不把重跑成功當作修復了所有 I/O 失敗。

## 尚未解決與下一步

1. UI 可視區閱讀排版與按章 API 優先；必須驗收 Markdown／TXT／EPUB 跨段落、畫面外全文選取、複製、重複段落筆記及閱讀進度。不能用互不相通的 SelectionArea 假裝完成。
2. 筆記逐條物件與有序索引：現有整陣列 blob 仍 O(N²)，session／磁碟／冷 canonical 成本仍隨累加歷史成長；之後仍可能撞 physical 上限。
3. 舊書顯式遷移與超量書出路；legacy 已有發布預檢，底層仍全文解碼。
4. server.lock 殘留與單本壞 manifest 拖垮書架：仍未修正。正常容量失敗不切 head，不能把它當成這兩項修復。
5. 持續輸入最大保存等待、可驗證差異復原與 crash 注入；目前仍停筆防抖保存完整草稿。
6. catalog 整檔改寫、正式提交前後歷史驗證、局部樹更新／正式 root 型事件：先按實際收益排程，不搶在 UI 體驗之前。

本輪完整驗收結果與 UI 對照將隨實際完成更新；不把歷史基準或外部 review 算成本次已重現。
