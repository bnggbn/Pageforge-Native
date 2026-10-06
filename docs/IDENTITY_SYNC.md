# 識別、內容承諾與多人多機（規劃）

本合約補充 [大型文件](LARGE_DOCUMENTS.md)。目前 Native 仍為本機單一 writer、每書一條 legacy 主線；ID 合約、root 型事件、actor/device streams、文件版本 DAG、簽章、同步與合併尚未實作。先定義資料關係，不能因模型已有 branch 欄位就宣稱多人可用。不同使用者預設分享／接收獨立副本；個人牆的所有權與整面分享見 [線索牆分享合約](WALL_SHARING.md)。

## ID 與雜湊分工

| 類型 | 用途 | 變動規則 |
| --- | --- | --- |
| workspaceId／documentId | 工作空間與文件身分 | 搬資料夾、改名不變；複製成獨立文件另發 ID |
| chapterId／blockId／noteId | 章節、邏輯段落、筆記身分 | 修改內容仍沿用；新增另發；拆分／合併記錄來源關係 |
| ownerId／wallId／topicId／cardInstanceId／edgeId | 個人副本控制者、牆、主題、卡片實例與紅線 | 自己多機同步保留；接收別人的獨立副本另發物件 ID 並承諾來源映射 |
| actorId／deviceId／streamId／keyId | 作者、裝置、單一寫入來源及簽署鍵 | 各自有身分生命週期，不以文件 ID 冒充人或裝置 |
| revisionId | 發布前可建立的版本識別 | 先生成，放入 canonical 事件，再算 SAI |
| eventSAI／chunkHash／contentRoot／notesRoot／wallRoot／bundleRoot | 不可變事件及內容承諾 | 對應內容改變即改變；包含格式／演算法識別 |

穩定邏輯 ID 可繼續用 CSPRNG UUIDv4，離線本機生成；ID 不代表權限或作者認證，也不用 UUID timestamp 判斷先後。[RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html#section-5.4)。章節與段落身分不由頁碼、陣列位置或可變標題決定。實體去重區塊則用 hash；同文不同段落各有邏輯 ID，但可共用相同 bytes 物件。初期不為每個字元分配 UUID；即時文字 CRDT 另有其操作／元素 ID 合約。

## 所有必要關聯都進證明範圍

Pageforge 新事件的共通 payload 至少綁定 schemaVersion、事件類型、namespace／owner、workspaceId、目標物件 ID、revisionId、actorId、deviceId、streamId、keyId、streamSequence、版本父節點與操作類型。正文事件承諾 contentRoot；個人筆記／牆事件承諾 notesRoot／wallRoot 及來源 documentId／版本／contentRoot；各類型有自己的必要欄位，不以缺省 root 混用語義。角色與鍵必須經可信授權資料認證；任意填入 actorId 不能證明作者。副本 owner、這次操作作者與原始作者分開。

documentParents 引用正文父版本的 eventSAI，驗證同一 namespace／workspace／document、合法父版本集合、無重複與循環。個人筆記／牆版本另使用有型別的父節點，驗證同一 owner 與物件範圍；來源書與別人的分享快照是 sourceRef，不冒充本地版本父節點。SDK 的 prevSAI 維持一個前驅，代表寫入來源鏈的前一事件，不能與文件父版本混用。合併版本可有多個文件父版本；需新增 Pageforge payload 及語義驗證，不把 SDK 單前驅演算法改成多前驅。

chapter／block ID、順序、長度及子物件 hash 由正文樹節點承諾；noteId、筆記內容 hash、引用版本及選取範圍由筆記樹承諾。樹根再進事件 canonical bytes，SAI 承諾事件與 prevSAI。證明事件不必逐版展開所有段落 ID；透過 root 及路徑 proof 可驗證 ID 到內容的映射。mutable 索引只加速查找，不能覆蓋已承諾關係。

eventSAI 是完成雜湊後的識別，不把自己放回自己的 payload，避免循環。revisionId 先生成；事件及其 SAI／簽章由外層紀錄保存。格式、排序、domain separation、Unicode 邊界與重複 ID 必須定義測試向量。VAX SDK 現有 SDTO validator 主要處理 string／number 欄位；documentParents 等複合欄位需要明確擴充驗證，不能僅因 canonical encoder 能輸出 array 就視為 schema 已支援。

## 正文、筆記與分章讀取

來源正文與個人的筆記／牆分別演進：正文事件承諾正文 root，個人正式事件承諾自己的 notesRoot／wallRoot，並引用指定正文版本與 contentRoot。需要同時保存的個人狀態由同一事件綁定，不把不同讀者的私人筆記收進來源書版本。正文按有序章節／區塊載入；筆記為 owner 範圍內獨立 noteId 索引子樹，短筆記用不可變 blob、長筆記可引用文本樹。新增筆記共用來源正文參照，不把筆記全文嵌入正文葉節點。章節到 noteId 的查找索引綁定 notesRoot；快取不是權威狀態。這是新合約，現有全文加 notes 的 legacy revision 保持原樣。

筆記 anchor 保存 documentId、目標版本 eventSAI／contentRoot、chapterId／blockId、選取範圍與引用上下文。樹區塊邊界與讀者段落不是同一種 ID；換版可用操作映射／穩定身分／原文上下文嘗試定位，歧義或已刪段落保留原引用並要求重綁。重綁亦是正式筆記事件，不以顯示快取默默改寫歷史。引用及孤立筆記不能被 GC 誤刪基準內容。

分章串流要限制在途請求、buffer／解壓量與快取；按章、區塊驗證後才交付對應閱讀範圍，不先累積全文再塞回一個 TextField。跨章選取用邏輯範圍，複製／匯出可以另按順序串流取得全文。此方案需與既有段落 anchor、EPUB section index 及 legacy JSON 制定 migration。

## 兩個圖：來源鏈與文件版本 DAG

每個可獨立離線寫入的 actor/device stream 保持自己的 genesis、連續 sequence 與 prevSAI，來源身分及 genesis 綁定須可驗證；同一使用者不同裝置不能共用一個可同時寫入的 head。備份恢復／複製為另一個可寫 replica 時建立新 stream，不能複製 sequence 後並行續寫同一條來源鏈。

文件版本 DAG 記錄內容如何演進，獨立於來源鏈。兩台裝置由共同版本 R 各產生 A、B，保留為兩個 heads；合併事件 M 的 documentParents 為 A、B，其 prevSAI 仍是合併者自己來源鏈的前一事件。這是 Pageforge 合併新內容狀態，不是修改／拼接既有 VAX 來源鏈。共同祖先與三方比較可借用 [Git merge-base 的模型](https://git-scm.com/docs/git-merge-base)。

第一階段的離線分支＋明確合併以同一 owner 的多裝置為範圍：不同 noteId 的新增可合併；同一筆記並行修改、刪除對修改、同段正文重疊修改與段落拆併列為衝突。非重疊修改也要驗證能精確套用共同基準，不能以最後 timestamp 覆蓋。合併後輸出新 root 與事件，保留原始兩邊版本與 provenance。

不同 owner 的卡片或整面牆預設先分享指定快照，收件者另建 ID 與自己的版本，保留來源；不得自動聯集所有人的筆記或合併私人布局。多人共同修改正文或同一面牆必須另外明確啟用及定義授權，不是預設同步行為。

即時共同打字是後續 CRDT／OT 階段，不把每個協同操作追加為正式 VAX。協同草稿保存自己的因果／操作資料，正式發布再承諾結果 root。[Automerge merge rules](https://automerge.org/docs/reference/under-the-hood/merge-rules/) 可作為因果與元素身分的參考，並不代表目前選定此套件或完成 Dart／Go 整合。

## 同步、認證與發布

- 初期同 owner 的每台裝置使用自己的 library 與本機 writer 鎖，透過同步 API 交換自己的不可變事件、物件及 heads；跨 owner 只交換明確選定的分享快照與必要依賴；不得讓多機直接共同寫 JSON 資料夾，server.lock 不能取代分散式協調。
- 同步事件先驗證 namespace、格式、物件 hash、來源鏈／sequence、該類型版本父節點、簽章及寫入權限。缺少前驅／物件進有界 pending 狀態等待依賴，不當成已驗證正式版本；錯誤內容拒絕。相同 eventSAI 冪等去重，同一 stream/sequence 不同內容保留衝突證據並阻止默默覆蓋。分享快照則依 [分享合約](WALL_SHARING.md) 驗證指定發布證明及依賴，不要求整條私人來源鏈。
- 多人作者認證使用每裝置鍵及明確成員／鍵授權關係。簽章在 SAE 外層，簽有 domain 的 eventSAI；actor/device/key 等身分欄位必須已在 SAE 承諾中。信任的公鑰登記、輪替／撤銷及離線事件的接納時點需單獨定義；hash 正確與 signature 正確都不等於當前具寫入權限。
- 同 owner 的同步分支，以及另外明確授權的共享正文分支，用 atomic CAS 發布 head；預期 head 已改就保存分支、明確合併，不重簽或改寫原事件。先保存並同步所有物件／事件，再發布可達 head，避免對外指向缺少的物件。同步不以裝置時鐘作全域排序。
- 伺服器可協調共享分支的可寫 head，但不能代替作者簽章；可信已知 head／收據或可交叉查核的 heads 才能增加對整鏈替換／回滾的偵測。單一來源簽章不能獨自證明伺服器沒隱藏另一支歷史。
- namespace、owner、角色和讀取權限由服務驗證，UUID／hash 都不是 access token；預設私人草稿不進共享版本。離線可用，重試不重複產生正式事件，隊列與同步資源均有上限。

## 相容與驗收階段

保留 legacy document actor（目前為 pageforge:documentId）、ID、full-text hashes、SAI 與 verifier，不把它重新解讀為使用者／裝置作者身分。root 型 payload、雙圖與新驗證器需 protocol／storage migration；舊歷史不重寫。多人功能啟用前仍使用本機單一 writer，不在個人閱讀流程加入帳戶／權限設定負擔。

先做 ID 與內容映射 proof／root／legacy 相容測試；再驗收同 owner 雙機離線並行、跨 owner 分享／副本來源隔離、亂序／重送／缺依賴、同段正文衝突、同筆記修改／刪除、anchor 重綁、跨 workspace 置換、錯誤簽章、鍵撤銷、複製 replica、head CAS 與發布中斷。最後才評估即時 CRDT、多人權限與 native release 效能。

ID 與版本圖不消除完整稽核成本：常用讀取驗證指定可信版本 root 下的章節與 proof，歷史摘要分頁；完整來源鏈／版本圖稽核處理事件數與可達物件數。若每版改全文，實體獨有內容仍可能接近版本數 × 正文大小。不能把按需驗證誤稱為所有歷史均已完整驗證。
