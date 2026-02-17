enum CLIError: Error, CustomStringConvertible {
    case noMainWindow
    case chatNotFound(String)
    case chatWindowNotOpen(String)
    case elementNotFound(String)

    var description: String {
        switch self {
        case .noMainWindow:
            "카카오톡 메인 윈도우를 찾을 수 없습니다."
        case .chatNotFound(let name):
            "채팅방 '\(name)'을(를) 찾을 수 없습니다."
        case .chatWindowNotOpen(let name):
            "채팅방 '\(name)' 윈도우를 열 수 없습니다."
        case .elementNotFound(let element):
            "\(element)을(를) 찾을 수 없습니다."
        }
    }
}
