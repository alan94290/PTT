import Foundation

/// Substrings used to recognize which screen PTT is currently showing us.
/// This is inherently a bit fragile — we're pattern-matching a UI meant for
/// humans — but these markers are stable pieces of PTT's chrome that have
/// been relied on by automation tools for years.
enum PTTScreen {
    static let pressAnyKey = ["任意鍵", "請按任意鍵"]
    static let duplicateLoginPrompt = "您想刪除其他重複登入的連線嗎"
    static let wrongPassword = ["密碼不對", "帳號或密碼", "screen資訊有誤"]
    static let mainMenuMarkers = ["離開，再見", "呼叫器", "(P)lay"]
    static let inBoardMarkers = ["文章選讀", "看板資訊/設定"]
    static let readingArticleMarkers = ["瀏覽", "頁"]
    static let over18Prompt = "滿18歲"
    static let boardNotFound = ["找不到該看板", "此看板不存在", "不存在看板"]

    static let pushPermissionGranted = "您覺得這篇文章"
    static let pushRateLimited = "禁止快速連續推文"
    static let pushForbidden = ["使用者不可發言", "禁止推薦", "禁止噓文"]

    static let saveConfirm = "確定要儲存檔案嗎"
    static let sendConfirm = "是否確定要送出這篇文章"
    static let signatureSelect = "選擇簽名檔"
    static let anonymousBoardPrompt = "請問要以匿名發表嗎"
}
