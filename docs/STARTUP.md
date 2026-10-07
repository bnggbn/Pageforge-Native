# 啟動生命週期

2026-10-07：本輪重構啟動與關閉，保留既有資料格式、VAX release、設定路徑及 API。

## 行為與責任

1. Bootstrap 發起一次 AppSession.open，啟動 Go sidecar 並等待 ready。
2. AppSession 建立書庫及設定 HTTP repository，由 Flutter DesignController 解讀及載入外觀。
3. 初始化完成才交給畫面並進入書架。外觀讀取／schema 錯誤保持預設外觀及既有錯誤提示，不寫回設定。
4. 取得資源後的初始化錯誤會清理已取得的資源，再顯示重新啟動；重複點重試不會建立多個 session。
5. Windows 關窗仍先經 CloseBoundary 保存／捨棄確認，再等待 session 關閉。啟動中關窗也等待 pending session 完成或失敗；完成的 session 直接關閉，不再進書架。
6. AppSession.close 與 BackendProcess.close 各共用同一個 Future，避免關窗、延遲初始化及 widget dispose 重複釋放。

Bootstrap 協調畫面與 pending session；AppSession 擁有 controller、兩個 HTTP client 及 BackendProcess；BackendProcess 管理程序管線。Go run 只處理 flags／signal，serve 持有 library、listener、server，以 defer 對應資源釋放，ready 輸出失敗也清理。

## 管線與邊界

- Go ready 為一行 JSON：origin 與 token。Dart 等待上限 15 秒，首行最多 4096 bytes；接受跨 chunk 訊息，拒絕缺少換行及無效 UTF-8／JSON。
- 僅接受 http、127.0.0.1、明確有效 port、無帳密／路徑／query／fragment，以及 64 個小寫十六進位字元的 token。token 不進 argv 或日誌，錯誤不回顯原始 ready frame。
- stderr 持續排空，最多保存 16 Ki 個 Dart UTF-16 units；容忍無效 UTF-8，診斷管線錯誤不替代 ready／程序退出狀態。
- 關閉 stdin 讓 Go 正常停止，Go HTTP shutdown 上限 3 秒。Dart 等待程序 5 秒，逾時 kill 後再等實際退出最多 2 秒，最後取消診斷訂閱。已退出 child 的 stdin 錯誤不阻止等待退出。
- 正常關閉會釋放 port 及 library/.pageforge/server.lock；強制終止、崩潰或斷電仍可能留下鎖或遺失尚未落盤輸入。本輪沒有實作失效鎖回收或差異復原。
- dispose 已無可顯示錯誤的視窗，仍發起清理；正常關窗路徑會等待清理，失敗交由 CloseBoundary 保留視窗。已開始的 session 關閉不支援重新連線；本輪不新增熱重啟功能。

## 驗收

- Go cmd/pageforge 測試啟動真實 loopback HTTP server：401／已授權狀態、父管線 EOF、context 取消、正常釋鎖及同書庫重啟；ready writer 失敗亦驗證 port／lock 釋放。
- Flutter 12 項新增測試：split frame、無效端點／token、frame／diagnostics 上限、EOF、診斷錯誤、啟動逾時、強制退出、外觀正常／fallback、初始化中斷、重試／dispose 及啟動中關窗等待。程序使用 injected fake，timeout 測試走真實 timer；Go 測試補足真實 server／library 生命週期。
- 測試僅用暫存 config／library／假程序，不讀寫私人書籍；Windows release 建置使用隔離複本，避免替換使用中的應用程式。
- 必要檢查：gofmt、go test ./...、go vet ./...、dart format、flutter test --no-pub、flutter analyze --no-pub、Windows release build。完整實機 GUI 手動操作、強制 crash 復原及安裝包驗收仍不由自動測試取代。

本輪結果：Go tests／vet 通過，Flutter 77 項通過／1 項既有 opt-in 大檔探針跳過，analyze 無問題；Windows release 建置通過。另以建置後的 Windows sidecar 真正子程序驗證 ready 格式、授權 HTTP、stdin EOF、exit code 0 及釋鎖。隔離產物位於 .preview/startup-validation/desktop/build/windows/x64/runner/Release，附後端與預設設定，不取代既有使用中產物。
