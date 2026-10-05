# JSON 外觀工作室

這一階段用來設計 Pageforge 自己的主題、書架及文字閱讀器。
入口是書架右上角的「外觀工作室」。選擇場景，調整屬性，或切換 JSON 編輯。
中央即時預覽使用自製示例文件與正式 BookTile、BookCover、LibraryHeader、ReadingInvitation、ArticleBody 元件。
預覽不讀取私人書籍，也不提交筆記或閱讀進度。

## 已完成

- 全域：紙張、文字、重點、森林、次要文字色彩及標題字體；書店／晨光／墨藍預設。
- 書架：閱讀引導顯示、書卡最大寬度、間距、五種封面線稿或依文件自動選擇。
- 文字閱讀器：文章最大寬度及內文行高；PDF、XLSX 原生版面不受這兩個欄位影響。
- 屬性與 JSON 共用一份設計資料；JSON 有 200 ms 防抖，無效輸入保持最後有效預覽。
- 復原／重做保留至多 50 次有效設計；離開時提示尚未套用的調整。
- 「套用並保存」成功才更新正式 UI；失敗保留工作室調整，書籍 VAX、草稿和進度獨立運作。
- 1440、960、600 寬度的工作室排版；窄視窗將屬性與預覽上下排列。

## JSON 合約與保存

預設值在專案／設定根目錄的 pageforge.design.json，與啟動設定 pageforge.config.json 分開。
Go 將完整本機覆寫保存為同目錄的 pageforge.design.local.json；不覆寫預設或 library。
build 腳本把預設設計一起放入 Release。PAGEFORGE_PROJECT_ROOT 同時決定這些設定的位置。
本機覆寫不提交 Git，刪除本機覆寫即可恢復預設；外部編輯後重啟，或在工作室重新載入。
尚未提供檔案監聽熱載入。

schemaVersion 固定為 1；完整欄位與界限見 schema/pageforge-design.schema.json。
Dart 與 Go 都驗證必填欄位、未知欄位、有限數值、字體與圖案列舉及 #RRGGBB 色彩。
JSON 最大 16 KiB；它只描述已實作元件的外觀，不包含任意 Dart／JavaScript、檔案路徑或遠端圖片。
缺少或損壞設定會顯示錯誤並以內建外觀啟動；需修正設定檔才能保存，不靜默覆蓋損壞資料。

GET /v1/design 回傳 document 與 revision；PUT /v1/design 傳入 document、expectedRevision。
revision 是內容 hash，用於拒絕過期保存；Go mutex 串行保存，先寫暫存檔、Sync，再 rename。
API 沿用 loopback、Bearer token、Origin 拒絕与容量限制。
此 hash 是保存衝突檢查，外觀尚未使用 VAX 歷史或建立分支。

## 責任邊界

- DesignDocument：不可變 JSON 與嚴格驗證。
- DesignController：已保存的全域外觀；DesignRepository 負責 Go API。
- StudioViewModel：工作室調整、復原／重做與套用生命週期。
- StudioScreen／Toolbar／SceneList／Inspector／Fields／JsonEditor：介面組裝與操作。
- StudioPreview：示例資料與正式元件預覽。
- DesignTheme：ThemeExtension，元件從目前 Theme 取得資料；樣式仍和元件放在一起。
- Go internal/design：文件驗證、容量界限、並行保存和原子寫入，與 library／VAX 分開。

## 後續階段

1. 預覽點選元件與屬性定位、完整色盤、JSON 語法標色及欄位提示。
2. 有穩定節點 ID 的場景樹、有限元件 registry、拖曳順序與響應式規則；先定 schema v2 migration。
3. 功能動作只能綁定已提供的 command ID，編輯預覽與實際操作分開。
4. 設計命名、匯入／匯出、VAX 版本／diff／Fork／Adopt，另定外觀文件模型與儲存合約。

第一版是固定場景的外觀編輯器；上述節點樹、任意畫布和動作編排尚未實作。
架構分層參照 Flutter 官方建議：https://docs.flutter.dev/app-architecture/recommendations。
