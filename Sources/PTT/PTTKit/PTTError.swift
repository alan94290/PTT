import Foundation

enum PTTError: Error, LocalizedError, Equatable {
    case notConnected
    case timedOut(context: String, screenSnapshot: String)
    case invalidCredentials
    case accountLoggedInElsewhere
    case boardNotFound(String)
    case pushRateLimited
    case pushNotAllowed(String)
    case unexpectedScreen(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "尚未連線到 PTT"
        case .timedOut(let context, let snapshot):
            let trimmed = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "等待逾時（\(context)），連線可能已中斷或伺服器沒有回應"
            }
            return "等待逾時（\(context)）。目前畫面內容：\n\(trimmed)"
        case .invalidCredentials:
            return "帳號或密碼錯誤"
        case .accountLoggedInElsewhere:
            return "此帳號已在別處登入"
        case .boardNotFound(let name):
            return "找不到看板 \(name)"
        case .pushRateLimited:
            return "推文太快，請稍後再試"
        case .pushNotAllowed(let reason):
            return "無法推文：\(reason)"
        case .unexpectedScreen(let detail):
            return "畫面狀態不如預期：\(detail)"
        }
    }
}
