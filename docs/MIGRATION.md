# Windows 遷移規格

本 repo 是獨立重寫，原 Pageforge Web repo 保留。
優先平台 Windows，Dart 做介面，Go 做後端；手機與 Web 需另外實作平台啟動與儲存介面。

## 第一階段

- 建立 Flutter Windows 原生介面與 Go sidecar。
- 書架分批入場、書卡浮起／焦點／按下回饋、閱讀轉場與模式切換；支援減少動畫。
- 動畫不得維持兩份 PDF／文字閱讀面板，父層更新不重播入場。
- 設定預設、本機覆寫與 library 路徑。
- 接通書架、MD／TXT 匯入與編輯、引用筆記、主線歷史／還原與文字 diff。
- 持久化草稿、重開恢復與保存失敗阻止切換。
- 驗證既有 library 主線；原始檔、manifest、versions、drafts 與 progress.json 保持相容。
- Go 自動測試與 vet、Flutter analyze／測試、Windows release 建置。

## 接續移植

1. Go EPUB／XLSX 解壓與 XML 解析、PDF 新檔匯入，沿用原有容量與 ZIP 限制。
2. 精確 block／列位置、PDF 頁碼保存、字級設定落盤與 Windows 關閉前 flush。
3. 沙盒 Fork／Diff／Adopt、封存／復原、草稿選取與捨棄、筆記 diff。
4. 原始檔／文字／歷史匯出、刪除與垃圾區、圖片驗證與版本化資產。
5. 大檔 Isolate／Go 工作排程、版本驗證快取、歷史分頁與實際負載量測。
6. 平台驗收、安裝包、手機與 Web；選用同步維持離線可用。

未完成的功能明列於 README，不因 UI 或資料模型存在就視為驗收完成。
資料庫和 VAX 協定改版須先定義 migration；不得直接改寫來源或歷史。
