# Pageforge Native

獨立於原 Pageforge Web repo 的 Flutter／Dart + Go 重構。第一個驗收平台是 Windows。

- Flutter 負責書架、閱讀、編輯、筆記與版本介面。
- Go 負責設定、library、匯入、VAX 驗證／提交、草稿、進度與文字 diff。
- 不需要 Node、Electron 或雲端帳號。Dart 套件由 Flutter Pub 管理，Go 套件由 Go Modules 管理。

## 啟動

需要 Flutter 3.41.7／Dart 3.11.5、Go 1.26 與 Visual Studio 的 C++ 桌面工作負載。

```powershell
.\scripts\build.ps1 -RunChecks
.\scripts\dev.ps1
```

建置產物：`apps/desktop/build/windows/x64/runner/Release/pageforge.exe`。
整個 Release 資料夾必須一起散布，包含 Flutter 資源、原生 DLL、Go 後端與設定。
直接啟動 Release 產物時，library 預設相對於產物資料夾；開發命令則使用專案內的 library。
可設定 `PAGEFORGE_PROJECT_ROOT` 指向專案／設定資料夾，或用 `PAGEFORGE_LIBRARY_ROOT` 指定書架。

未開啟 Windows Developer Mode 時，build 腳本會針對 Flutter plugin 目錄建立 junction，
不變更系統設定。首次先執行 build，dev 使用已解析的套件。

書架採書店風格排版、五種向量封面、書脊光影與可開書的閱讀引導區。設計細節見 [視覺規格](docs/DESIGN.md)。

書架分批入場、書卡滑鼠／鍵盤焦點回饋、閱讀轉場與模式切換使用輕量原生動畫。
遵守系統「減少動畫」設定；不使用持續播放效果，切換只保留一份閱讀面板。

外觀工作室提供主題預設、屬性／JSON 編輯、書架及文字閱讀器即時預覽（含段落額外間距），套用後由 Go 保存，重開恢復。入口在書架右上角；合約與限制見 [JSON 外觀工作室](docs/DESIGN_STUDIO.md)。任意拖曳場景及設計 VAX 歷史仍待實作。

段落筆記：選取文字後，桌面右鍵／觸控長按選單提供「作筆記」。保存後小雲緊跟段落最後一行的文字末端並顯示筆記數，點雲可查看原始引用與筆記。跨段選取會在涵蓋的段落各顯示小雲，且不影響全文複製。作筆記範圍遇到下一個 Markdown 標題即停止，一般複製保留完整選取。

原「筆記」頁籤改為「線索牆」（Evidence Wall）：每本書可建立多個命名主題，挑選相關筆記加入畫布；同一筆記可出現在多個主題，布局與紅線獨立。既有筆記及布局保留在「全部線索」。按住卡片標題或內容會浮起，拖曳整理位置；點一下內容查看筆記。拖曳圖釘或依序點兩個圖釘連紅線；可點紅線編輯關係標籤，也能回到原文。布局由 Go 保存並檢查並行更新。詳見 [段落筆記與線索牆](docs/EVIDENCE_WALL.md)。

## 本階段能力

| 格式 | 新檔匯入 | 閱讀 | 筆記 | 直接改文字 |
| --- | --- | --- | --- | --- |
| Markdown／TXT | 支援 | 支援 | 支援 | 支援 |
| PDF | 待移植 | 可讀既有 library 原始檔 | 支援 | 未提供 |
| EPUB | 待移植 | 可讀既有 library 章節投影 | 支援 | 未提供 |
| XLSX | 待移植 | 可讀既有 library 工作表投影 | 支援 | 未提供 |

文字編輯、筆記與還原新增 VAX 主線版本；支援文字 inline diff。線索牆布局獨立保存，尚未接入 VAX 布局歷史。個人牆的所有權與整面快照分享／獨立副本匯入仍為 [規劃](docs/WALL_SHARING.md)，[單卡發布／接收](docs/CARD_PUBLISHING.md) 亦待實作，目前沒有分享功能。同 owner 並行修改將 [另開新鏈保留版本副本](docs/IDENTITY_SYNC.md)，不要求分支衝突合併；目前正式保存／布局衝突仍回傳錯誤。
段落小雲與原文定位支援 Markdown／TXT／EPUB 文字投影；EPUB 按章節隔離，舊筆記只在原章節能唯一定位時掛上小雲。PDF／XLSX 可做一般筆記及使用線索牆，精確段落定位待補。Android 長按選單已做觸控 widget 測試，手機應用程式尚未建置驗收。
未改文字的筆記草稿保存基準引用；並行 draft token 衝突另存副本，保存失敗阻止切換。
Markdown 支援跨段落拖曳、包含畫面外段落的全文全選／複製，引用只保存實際選中範圍；文字閱讀以捲動比例恢復，EPUB／XLSX 保存區段；PDF 頁碼保存、XLSX 列定位與舊版 block anchor 精確恢復待補。
Markdown／TXT／EPUB 段落預設多留一行視覺間距，可在外觀工作室調整；不插入原文換行，引用、複製及 VAX 內容保持原樣。
Markdown／TXT 編輯改為分節 TextField：每次輸入更新目前節，草稿保存與正式保存時組回全文；工具列可切節與複製全文，Ctrl+A／undo 作用於目前節。reading.editorSectionUnits 預設16,000個 UTF-16單位，可設定1,000–65,536；Unicode／CRLF 保留，跨節選取與全文件 undo 尚未做。
Markdown 閱讀為全文選取仍使用完整佈局；大型文章的可視區渲染與選取索引仍待優化。編輯控件百萬字對照見 [本輪報告](docs/experiments/REVIEW_FOLLOWUP.md)，不代表整體大檔體驗已驗收。
圖片暫以文字說明呈現，不自動讀取本機或遠端圖片；圖片資產服務尚未移植。
主線包含既有 adopt 事件時可驗證；關閉時可捨棄目前草稿。沙盒操作、多草稿選擇、筆記 diff、匯出與刪除介面尚未移植。
Windows 正常關閉會提示保存／捨棄目前草稿／取消，保存失敗保留視窗；也涵蓋未套用的外觀 JSON。保存後可續寫草稿，正式版本仍另外建立。強制終止與斷電仍可能遺失最後一次防抖期間的輸入。

後端失敗回應提供穩定 code 與可讀 error，Flutter 共用解析；區分文件不存在、依賴缺失、完整性失敗、容量超限、I/O 與並行衝突。保留舊回應相容，儲存錯誤不回傳本機路徑；詳見 [錯誤代碼合約](docs/API_ERRORS.md)。

新匯入書預設使用內容定址正文樹與獨立筆記 blob：筆記版本共用正文，小修改可共用區塊，正式 VAX 保持原本全文 hash；架構、格式／設定及舊程式限制見 [內容物件](docs/CONTENT_OBJECTS.md)。舊書保持全文 JSON 讀寫，不自動遷移；操作式編輯、分章讀取與差異復原仍待完成。

舊 library 格式保持相容。請先關閉使用該 library 的 Web 或桌面服務，並備份後再指定舊路徑。
新 repo 預設使用自己的 library，沒有複製私人書籍。

Native 的一般 Go Load／Commit 回傳目前版本與歷史摘要；objects-v1 冷讀以串流正文雜湊及逐版筆記驗證歷史，不保留每版全文／筆記。舊草稿、diff 與還原按需取指定版本，歷史查看不淘汰 head 快取。LoadHistory／CommitHistory 與不帶 view=reader 的 HTTP 保留完整歷史相容介面及 aggregate 上限；legacy 仍需完整解碼。快取保留 head 與依賴／metadata，每次重驗實際位元組，暖讀仍有歷史 I/O 成本。新舊格式均在切 head 前預檢容量，舊書遷移仍待做；[review 修正與剩餘問題](docs/experiments/REVIEW_FOLLOWUP.md)。Go 另提供批次匯入索引。HTTP deadline 涵蓋完整回應。設定與 Git 式差異儲存評估見 [版本儲存評估](docs/VERSION_STORAGE.md)。冷讀取與完整歷史 I/O 仍待改善。大型文本的 opt-in 探針、限制與實測瓶頸見 [基準報告](docs/experiments/LARGE_DOCUMENT_BASELINE.md)；目前未通過百萬字體驗驗收。

架構與分階段驗收見 [架構](docs/ARCHITECTURE.md)、[遷移規格](docs/MIGRATION.md)。
