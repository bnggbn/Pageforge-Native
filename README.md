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

## 本階段能力

| 格式 | 新檔匯入 | 閱讀 | 筆記 | 直接改文字 |
| --- | --- | --- | --- | --- |
| Markdown／TXT | 支援 | 支援 | 支援 | 支援 |
| PDF | 待移植 | 可讀既有 library 原始檔 | 支援 | 未提供 |
| EPUB | 待移植 | 可讀既有 library 章節投影 | 支援 | 未提供 |
| XLSX | 待移植 | 可讀既有 library 工作表投影 | 支援 | 未提供 |

文字編輯、筆記与還原新增 VAX 主線版本；支援文字 inline diff。
未改文字的筆記草稿保存基準引用；並行 draft token 衝突另存副本，保存失敗阻止切換。
Markdown 支援跨段落拖曳、包含畫面外段落的全文全選／複製，引用只保存實際選中範圍；文字閱讀以捲動比例恢復，EPUB／XLSX 保存區段；PDF 頁碼保存、XLSX 列定位與舊版 block anchor 精確恢復待補。
Markdown 為全文選取使用完整佈局；大型文章的分塊渲染與選取索引仍待優化。
圖片暫以文字說明呈現，不自動讀取本機或遠端圖片；圖片資產服務尚未移植。
主線包含既有 adopt 事件時可驗證；沙盒操作、草稿選擇／捨棄、筆記 diff、匯出與刪除介面尚未移植。
系統強制終止與最後一次防抖保存間的輸入仍可能未落盤；Windows 關閉攔截待補。

舊 library 格式保持相容。請先關閉使用該 library 的 Web 或桌面服務，並備份後再指定舊路徑。
新 repo 預設使用自己的 library，沒有複製私人書籍。

架構與分階段驗收見 [架構](docs/ARCHITECTURE.md)、[遷移規格](docs/MIGRATION.md)。
