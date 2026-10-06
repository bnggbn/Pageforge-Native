# 識別、內容承諾與多人多機（規劃）

本合約補充 [大型文件](LARGE_DOCUMENTS.md)。目前 Native 仍為本機單一 writer、每書一條 legacy 主線；ID 合約、root 型事件、actor/device streams、版本副本圖、簽章與同步尚未實作。先定義資料關係，不能因模型已有 branch 欄位就宣稱多人可用。不同使用者預設分享／接收獨立副本；個人牆的所有權與整面分享見 [線索牆分享合約](WALL_SHARING.md)。

## ID 與雜湊分工

| 類型 | 用途 | 變動規則 |
| --- | --- | --- |
| workspaceId／documentId | 工作空間與文件身分 | 搬資料夾、改名不變；複製成獨立文件另發 ID |
| chapterId／blockId／noteId | 章節、邏輯段落、筆記身分 | 修改內容仍沿用；新增另發；拆分／合併記錄來源關係 |
| ownerId／wallId／topicId／cardInstanceId／edgeId | 個人副本控制者、牆、主題、卡片實例與紅線 | 自己多機同步保留；接收別人的獨立副本另發物件 ID 並承諾來源映射 |
| actorId／deviceId／streamId／keyId | 作者、裝置、單一寫入來源及簽署鍵 | 各自有身分生命週期，不以文件 ID 冒充人或裝置 |
| chainId | 可獨立續寫的版本副本鏈 | 有效並行修改另發，來源基準由 forkedFrom 承諾 |
| revisionId | 發布前可建立的版本識別 | 先生成，放入 canonical 事件，再算 SAI |
| eventSAI／chunkHash／contentRoot／notesRoot／wallRoot／bundleRoot | 不可變事件及內容承諾 | 對應內容改變即改變；包含格式／演算法識別 |

穩定邏輯 ID 可繼續用 CSPRNG UUIDv4，離線本機生成；ID 不代表權限或作者認證，也不用 UUID timestamp 判斷先後。[RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html#section-5.4)。章節與段落身分不由頁碼、陣列位置或可變標題決定。實體去重區塊則用 hash；同文不同段落各有邏輯 ID，但可共用相同 bytes 物件。初期不為每個字元分配 UUID；即時文字 CRDT 另有其操作／元素 ID 合約。

## 所有必要關聯都進證明範圍

Pageforge 新事件的共通 payload 至少綁定 schemaVersion、事件類型、namespace／owner、workspaceId、目標物件 ID、revisionId、actorId、deviceId、streamId、keyId、streamSequence、版本父節點與操作類型。正文事件承諾 contentRoot；個人筆記／牆事件承諾 notesRoot／wallRoot 及來源 documentId／版本／contentRoot；各類型有自己的必要欄位，不以缺省 root 混用語義。角色與鍵必須經可信授權資料認證；任意填入 actorId 不能證明作者。副本 owner、這次操作作者與原始作者分開。

documentParents 引用正文父版本的 eventSAI，驗證同一 namespace／workspace／document、合法父版本集合、無重複與循環。個人筆記／牆版本另使用有型別的父節點，驗證同一 owner 與物件範圍；來源書與別人的分享快照是 sourceRef，不冒充本地版本父節點。SDK 的 prevSAI 維持一個前驅，代表寫入來源鏈的前一事件，不能與文件父版本混用。第一階段每個版本只有一個內容父版本，並行修改另開副本鏈；不同副本間以有型別的來源關聯保留脈絡，不產生強制合併事件。需新增 Pageforge payload 及語義驗證，不修改 SDK 單前驅原語。

chapter／block ID、順序、長度及子物件 hash 由正文樹節點承諾；noteId、筆記內容 hash、引用版本及選取範圍由筆記樹承諾。樹根再進事件 canonical bytes，SAI 承諾事件與 prevSAI。證明事件不必逐版展開所有段落 ID；透過 root 及路徑 proof 可驗證 ID 到內容的映射。mutable 索引只加速查找，不能覆蓋已承諾關係。

eventSAI 是完成雜湊後的識別，不把自己放回自己的 payload，避免循環。revisionId 先生成；事件及其 SAI／簽章由外層紀錄保存。格式、排序、domain separation、Unicode 邊界與重複 ID 必須定義測試向量。VAX SDK 現有 SDTO validator 主要處理 string／number 欄位；documentParents 等複合欄位需要明確擴充驗證，不能僅因 canonical encoder 能輸出 array 就視為 schema 已支援。

## 正文、筆記與分章讀取

來源正文與個人的筆記／牆分別演進：正文事件承諾正文 root，個人正式事件承諾自己的 notesRoot／wallRoot，並引用指定正文版本與 contentRoot。需要同時保存的個人狀態由同一事件綁定，不把不同讀者的私人筆記收進來源書版本。正文按有序章節／區塊載入；筆記為 owner 範圍內獨立 noteId 索引子樹，短筆記用不可變 blob、長筆記可引用文本樹。新增筆記共用來源正文參照，不把筆記全文嵌入正文葉節點。章節到 noteId 的查找索引綁定 notesRoot；快取不是權威狀態。這是新合約，現有全文加 notes 的 legacy revision 保持原樣。

筆記 anchor 保存 documentId、目標版本 eventSAI／contentRoot、chapterId／blockId、選取範圍與引用上下文。樹區塊邊界與讀者段落不是同一種 ID；換版可用操作映射／穩定身分／原文上下文嘗試定位，歧義或已刪段落保留原引用並要求重綁。重綁亦是正式筆記事件，不以顯示快取默默改寫歷史。引用及孤立筆記不能被 GC 誤刪基準內容。

分章串流要限制在途請求、buffer／解壓量與快取；按章、區塊驗證後才交付對應閱讀範圍，不先累積全文再塞回一個 TextField。跨章選取用邏輯範圍，複製／匯出可以另按順序串流取得全文。此方案需與既有段落 anchor、EPUB section index 及 legacy JSON 制定 migration。

## 來源鏈、版本副本與持續創作

每個可獨立離線寫入的 actor/device stream 保持自己的 genesis、連續 sequence 與 prevSAI，來源身分及 genesis 綁定須可驗證；同一使用者不同裝置不能共用一個可同時寫入的 head。備份恢復／複製為另一個可寫 replica 時建立新 stream，不能複製 sequence 後並行續寫同一條來源鏈。

版本圖記錄來源基準與各份副本的演進，第一階段不要求分支合併。兩台裝置從共同版本 R 產生 A、B 時保留兩份；正在編輯的裝置繼續自己的副本，其他裝置的版本可稍後查看。介面用「另一份版本／保留副本」描述，不讓工程用 conflict 或 merge 流程打斷創作，不依時間戳選一份並丟掉另一份。

有效並行寫入遇到 head／revision CAS 不符時，先固定自己的基準、正文、筆記與布局所需參照，再冪等建立新的 chainId 及可持久化副本。不能把過期操作直接套到最新版本、把最新正文與舊筆記任意拼接，或覆蓋另一份。完成落盤後才提示「已保留為另一份版本，你可以繼續」；失敗保留記憶體修改並明示未保存，不假稱已保護。CAS 仍是資料保護，不因介面不處理合併而移除。

新副本正式保存時建立獨立 VAX 鏈，使用新的 streamId／genesis；首個正式事件承諾 chainId、forkedFrom（原始基準版本 SAI／root）、操作作者及本地結果 root。並行的另一份 head 另作參照，不冒充操作基準。既有事件、streamSequence 與 prevSAI 都不改寫，也不在同一 stream/sequence 簽兩份不同內容。跨鏈基準須驗證型別、owner、物件身分及可達來源；來源缺失時不宣布來源證明完整。

自動保護草稿只新建 draft／generation 及復原資料，不因一次碰撞便提交正式 VAX；使用者明確保存才建立新鏈的正式事件。布局副本也要保留它依賴的筆記版本，使卡片／紅線能完整還原。已有保存操作遇到並行更新，可將該次明確保存的結果發布在新鏈；使用 operationId 記錄回應與副本結果，超時重送不重複生鏈。同一副本後續沿自己的鏈續寫。

未變內容以不可變物件／root 共用，建立副本不複製全部歷史或全部正文；基準、筆記、布局、發布與復原資料的可達物件均需保留。索引先寫物件再原子發布；跨裝置各自持有活動副本，不同步一個會搶回焦點的全域 active pointer。副本數量／bytes／復原保留量必須有界；達上限保留輸入並通知，不能靜默刪另一份或無限重試。

使用者可稍後查看差異、選一份繼續、另存或封存另一份；比較是輔助，不是繼續編輯的前置條件。逐欄位、逐段衝突合併與自動聯集筆記不屬於第一階段。不同 owner 的卡片或整面牆仍走 [發布卡片](CARD_PUBLISHING.md)／[分享快照](WALL_SHARING.md)，建立自己的副本，不共享私人牆的可寫 head。

錯誤簽章、內容損壞、非法端點、越權或同一 stream/sequence 出現不同內容屬驗證失敗，不能用自動另開鏈當成已驗證資料。新鏈無法解決磁碟滿、連線失敗或遺失依賴；這些仍須保存錯誤處理。即時共同打字如日後需要，再另定 CRDT／OT 合約，目前不安裝協同套件。

目前只有 WorkingCopy 在 draft token 衝突時新建草稿 ID；正式 Commit 與線索牆 SaveEvidence 仍回傳衝突，legacy verifier 拒絕 BranchID。完整新鏈、活動副本切換與副本管理尚未實作，需要 storage／protocol migration；不得把草稿副本稱為正式 VAX 新鏈。

## 同步、認證與發布

- 初期同 owner 的每台裝置使用自己的 library 與本機 writer 鎖，透過同步 API 交換自己的不可變事件、物件及 heads；跨 owner 只交換明確選定的分享快照與必要依賴；不得讓多機直接共同寫 JSON 資料夾，server.lock 不能取代分散式協調。
- 同步事件先驗證 namespace、格式、物件 hash、來源鏈／sequence、該類型版本父節點、簽章及寫入權限。缺少前驅／物件進有界 pending 狀態等待依賴，不當成已驗證正式版本；錯誤內容拒絕。相同 eventSAI 冪等去重，同一 stream/sequence 不同內容保留衝突證據並阻止默默覆蓋。分享快照則依 [分享合約](WALL_SHARING.md) 驗證指定發布證明及依賴，不要求整條私人來源鏈。
- 多人作者認證使用每裝置鍵及明確成員／鍵授權關係。簽章在 SAE 外層，簽有 domain 的 eventSAI；actor/device/key 等身分欄位必須已在 SAE 承諾中。信任的公鑰登記、輪替／撤銷及離線事件的接納時點需單獨定義；hash 正確與 signature 正確都不等於當前具寫入權限。
- 同 owner 的同步分支，以及另外明確授權的共享正文分支，用 atomic CAS 發布 head；預期 head 已改就保留獨立副本鏈，讓目前副本繼續，不要求合併，不重簽或改寫原事件。先保存並同步所有物件／事件，再發布可達 head，避免對外指向缺少的物件。同步不以裝置時鐘作全域排序。
- 伺服器可協調共享分支的可寫 head，但不能代替作者簽章；可信已知 head／收據或可交叉查核的 heads 才能增加對整鏈替換／回滾的偵測。單一來源簽章不能獨自證明伺服器沒隱藏另一支歷史。
- namespace、owner、角色和讀取權限由服務驗證，UUID／hash 都不是 access token；預設私人草稿不進共享版本。離線可用，重試不重複產生正式事件，隊列與同步資源均有上限。

## 相容與驗收階段

保留 legacy document actor（目前為 pageforge:documentId）、ID、full-text hashes、SAI 與 verifier，不把它重新解讀為使用者／裝置作者身分。root 型 payload、版本副本與新驗證器需 protocol／storage migration；舊歷史不重寫。多人功能啟用前仍使用本機單一 writer，不在個人閱讀流程加入帳戶／權限設定負擔。

先做 ID 與內容映射 proof／root／legacy 相容測試；再驗收同 owner 雙機離線並行、跨 owner 分享／副本來源隔離、亂序／重送／缺依賴、同段正文／同筆記並行修改與刪除的副本完整保留、布局依賴、不中斷續寫、operationId 重試、chainId 與 stream 身分、anchor 重綁、跨 workspace 置換、錯誤簽章、鍵撤銷、複製 replica、head CAS 與發布中斷。最後才評估即時 CRDT、多人權限與 native release 效能。

ID 與版本圖不消除完整稽核成本：常用讀取驗證指定可信版本 root 下的章節與 proof，歷史摘要分頁；完整來源鏈／版本圖稽核處理事件數與可達物件數。若每版改全文，實體獨有內容仍可能接近版本數 × 正文大小。不能把按需驗證誤稱為所有歷史均已完整驗證。
