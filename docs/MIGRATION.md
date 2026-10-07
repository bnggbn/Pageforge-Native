# Windows 遷移規格

本 repo 是獨立重寫，原 Pageforge Web repo 保留。
優先平台 Windows，Dart 做介面，Go 做後端；手機與 Web 需另外實作平台啟動與儲存介面。

## 第一階段

- 建立 Flutter Windows 原生介面與 Go sidecar。
- 書店風格書架：襯線標題、向量封面、書脊光影、閱讀引導；拆分封面與書架區塊元件，見 [視覺規格](DESIGN.md)。
- 書架分批入場、書卡浮起／焦點／按下回饋、閱讀轉場與模式切換；支援減少動畫。
- 動畫不得維持兩份 PDF／文字閱讀面板，父層更新不重播入場。
- 設定預設、本機覆寫與 library 路徑。
- 外觀責任分工：Flutter 擁有 design／theme schema、預設、驗證及套用；Go internal/settings 只保存不透明 JSON，保留既有檔案與 API、不重複 UI 規則。[合約與驗收](DESIGN_STUDIO.md)。
- JSON 外觀工作室：主題、固定書架／文字閱讀場景、屬性與 JSON 即時預覽、復原重做、保存後套用及重開恢復；[外觀合約](DESIGN_STUDIO.md)。場景樹／拖曳／動作編排／設計 VAX 尚未實作。
- 接通書架、MD／TXT 匯入與分節編輯、引用筆記、主線歷史／還原與文字 diff；編輯按鍵只更新目前節，全文於保存／複製時組合，UTF-16 安全範圍與 Unicode／CRLF 保留，節大小可配置。跨節選取、全文件 undo、閱讀可視區及按章 API 尚未做；[本機驗證與限制](experiments/REVIEW_FOLLOWUP.md)。
- Markdown 共用文章選取區，驗收跨段落拖曳、畫面外段落全選／複製與精確引用；TXT／EPUB 文字使用同一選取區。
- 段落筆記：桌面右鍵與觸控長按選單、小雲數量、跨段範圍、查看引用及原文定位；保留整篇文章選取，作筆記在下一個 Markdown 標題前裁切；小雲緊跟段落末行文字終點，EPUB 新舊筆記按章節隔離，從線索牆定位後手動切章不重播跳轉。
- 線索牆取代筆記頁籤：卡片標題與整片內容可拖曳、按住浮起且支援減少動畫、圖釘紅線、關係標籤、平移縮放、多個命名主題、筆記挑選、獨立布局保存與並行衝突檢查；舊 schema v1 首次保存為 v2 時保留原檔備份；[合約與限制](EVIDENCE_WALL.md)。
- 持久化草稿、重開恢復與保存失敗阻止切換；Windows 正常關閉提供保存／捨棄目前草稿／取消，也涵蓋外觀工作室；失敗不關閉。
- 驗證既有 library 主線；舊書原始檔、manifest、versions、drafts 與 progress.json 保持相容。新物件格式以 manifest marker 區分，舊程式尚不能讀取。
- 一般 Go Load／Commit 的目前快照＋歷史摘要、objects-v1 串流正文雜湊與逐版筆記驗證／釋放、指定舊版按需還原／diff、只留 head 的驗證快取；LoadHistory／CommitHistory 與舊 HTTP 全歷史相容，legacy 仍完整解碼。新舊格式均有切 head 前容量預檢。另有精簡 reader HTTP 投影、舊草稿按需取基準版本、內容雜湊驗證快取、單檔／整本歷史讀取限制、批次匯入索引與完整 HTTP deadline；[版本儲存評估](VERSION_STORAGE.md)。
- 線索牆圖釘移動只重繪紅線，卡片只更新活動位置；關係標籤重用排版並釋放，不繪製視窗外紅線。
- VAX canonical／genesis／SAI 改為官方 Go SDK v0.0.0 直接依賴，移除本地協定實作；後端診斷英文、Flutter 依代碼顯示中文。[依賴與驗收](VAX_DEPENDENCY.md)。
- 新匯入書預設 objects-v1：依內容分塊的正文樹、獨立筆記 blob、物件去重及有界驗證；正式 VAX 維持還原全文雜湊，舊書不遷移，配置／架構見 [內容物件](CONTENT_OBJECTS.md)。尚未提供操作式編輯、分章 API、差異復原或 root 型正式事件。
- 後端 typed 錯誤代碼、code／error JSON、必要依賴缺失／完整性／容量／I/O 分流、Flutter 共用解析與舊回應相容；草稿 CAS 以代碼判斷，正式並行新鏈尚未實作；[錯誤合約與本輪結論](API_ERRORS.md)。
- Go 自動測試與 vet、Flutter analyze／測試、Windows release 建置。

## 接續移植

1. Go EPUB／XLSX 解壓與 XML 解析、PDF 新檔匯入，沿用原有容量與 ZIP 限制。
2. 精確 block／列位置、PDF 頁碼保存、字級設定落盤。
3. 定時草稿復原：最大保存等待、合併在途修改、checkpoint／增量日誌、損壞尾端與重開選擇、失效鎖安全回收；[規劃與驗收](DRAFT_RECOVERY.md)。
4. 沙盒 Fork／Diff／Adopt、封存／復原、多草稿選取／逐份管理、筆記 diff。
5. 原始檔／文字／歷史匯出、刪除與垃圾區、圖片驗證與版本化資產。
6. 大檔操作模型／局部樹更新、按章 API、舊書物件遷移、Isolate／Go 工作排程、歷史分頁與冷驗證優化及實際負載量測；Markdown 分塊渲染必須保留跨段落及全文選取能力。復原／正式版本分層及 VAX 相容界線見 [大型文件規劃](LARGE_DOCUMENTS.md)。
7. 個人線索牆所有權／卡片實例 ID 與布局 VAX 歷史；[單卡發布／接收](CARD_PUBLISHING.md) 與整面牆快照匯出／匯入，保留主題、布局、紅線及來源，建立獨立副本而非自動跨人合併；[分享與遷移合約](WALL_SHARING.md)。跨書籍線索、PDF／XLSX 精確定位及孤立筆記手動重綁仍待補。
8. [同 owner 並行修改新鏈副本](IDENTITY_SYNC.md)：草稿／正文／筆記／布局完整保留、可繼續編輯，不要求分支衝突合併；目前只有 draft token 衝突另存草稿。平台驗收、安裝包、手機與 Web；選用同步維持離線可用。

未完成的功能明列於 README，不因 UI 或資料模型存在就視為驗收完成。
資料庫和 VAX 協定改版須先定義 migration；不得直接改寫來源或歷史。
