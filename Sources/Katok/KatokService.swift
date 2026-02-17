import AppKit
import AXKit

enum KatokService {
    static let bundleId = "com.kakao.KakaoTalkMac"

    // MARK: - App & Window

    static func getApp() throws -> AXElement {
        try AXPermission.ensureGranted()
        try ensureAppRunning()
        return try AXElement.application(bundleIdentifier: bundleId)
    }

    static func ensureAppRunning() throws {
        let workspace = NSWorkspace.shared

        if workspace.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleId]
        try process.run()
        process.waitUntilExit()

        for _ in 0 ..< 10 {
            Thread.sleep(forTimeInterval: 0.5)
            if workspace.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) {
                Thread.sleep(forTimeInterval: 0.5)
                return
            }
        }
    }

    private static func findMainWindow(in windows: [AXElement]) -> AXElement? {
        // identifier와 title을 배치로 읽어 IPC 호출 절반으로 줄임
        let windowAttrs = windows.map { ($0, $0.attributes(.identifier, .title)) }

        if let (window, _) = windowAttrs.first(where: { $0.1.0 == "Main Window" }) {
            return window
        }
        return windowAttrs.first(where: { $0.1.1 == "카카오톡" })?.0
    }

    static func getMainWindow() throws -> AXElement {
        var app = try getApp()

        if let mainWindow = findMainWindow(in: app.windows) {
            return mainWindow
        }

        if let runningApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })
        {
            let pid = runningApp.processIdentifier

            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x12, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x12, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.postToPid(pid)
            keyUp?.postToPid(pid)

            Thread.sleep(forTimeInterval: 0.5)

            app = try getApp()

            if let mainWindow = findMainWindow(in: app.windows) {
                return mainWindow
            }
        }

        throw CLIError.noMainWindow
    }

    // MARK: - Tab Navigation

    private static func getKatokPid() throws -> pid_t {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })
        else {
            throw CLIError.elementNotFound("카카오톡 프로세스")
        }
        return app.processIdentifier
    }

    private static func sendCmdKey(_ virtualKey: CGKeyCode, to pid: pid_t) {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.postToPid(pid)
        keyUp?.postToPid(pid)
    }

    static func goToFriendsTab() throws {
        _ = try getMainWindow()
        let pid = try getKatokPid()
        sendCmdKey(0x12, to: pid)
        Thread.sleep(forTimeInterval: 0.3)
    }

    static func goToChatsTab() throws {
        _ = try getMainWindow()
        let pid = try getKatokPid()
        sendCmdKey(0x13, to: pid)
        Thread.sleep(forTimeInterval: 0.3)
    }

    private static func findChatTable(in mainWindow: AXElement) throws -> AXElement {
        for attempt in 0 ..< 8 {
            if let table = try? mainWindow.findFirst(role: AXRole.table, maxDepth: 10) {
                return table
            }

            if attempt < 7 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        throw CLIError.elementNotFound("채팅 목록 테이블")
    }

    // MARK: - Friends

    private static let excludedSections = ["생일인 친구", "채널", "업데이트한 친구", "내 기본프로필"]

    static func getFriendsSections() throws -> [FriendSection] {
        try goToFriendsTab()

        let mainWindow = try getMainWindow()

        guard let outline = try? mainWindow.findFirst(role: AXRole.outline, maxDepth: 10) else {
            throw CLIError.elementNotFound("친구 목록")
        }

        let rows = outline.children.filter { $0.role == AXRole.row }
        var sections: [FriendSection] = []
        var currentSectionName: String?
        var currentFriends: [Friend] = []
        var isExcludedSection = false

        for row in rows {
            guard let cell = row.children.first(where: { $0.role == AXRole.cell }) else { continue }

            var sectionHeaderText: String?
            var name: String?
            var statusMessage: String?

            for child in cell.children {
                let (role, identifier, stringValue) = child.attributes(
                    .role,
                    .identifier,
                    .stringValue,
                )
                guard role == AXRole.staticText else { continue }

                let id = identifier ?? ""
                let text = stringValue ?? ""

                if id == "_NS:93" {
                    sectionHeaderText = text
                } else if id == "Display Name" {
                    name = text
                } else if id == "Status Message" {
                    statusMessage = text
                }
            }

            if let headerText = sectionHeaderText, !headerText.isEmpty {
                if let sectionName = currentSectionName, !currentFriends.isEmpty {
                    sections.append(FriendSection(name: sectionName, friends: currentFriends))
                }
                currentSectionName = headerText
                currentFriends = []
                isExcludedSection = excludedSections.contains { headerText.contains($0) }
                continue
            }

            if isExcludedSection {
                continue
            }

            if let friendName = name, !friendName.isEmpty {
                if friendName.hasPrefix("친구의 생일을") || friendName.hasPrefix("채널 ") {
                    continue
                }
                currentFriends.append(Friend(name: friendName, statusMessage: statusMessage))
            }
        }

        if let sectionName = currentSectionName, !currentFriends.isEmpty {
            sections.append(FriendSection(name: sectionName, friends: currentFriends))
        }

        return sections
    }

    static func getFriendsList() throws -> [Friend] {
        try getFriendsSections().flatMap(\.friends)
    }

    // MARK: - Chats

    static func getChatList(limit: Int = 50, offset: Int = 0) throws -> [ChatRoom] {
        try goToChatsTab()

        let mainWindow = try getMainWindow()
        let table = try findChatTable(in: mainWindow)

        let rows = table.attributeOrNil("AXRows", as: [AXElement].self) ?? table.children
            .filter { $0.role == AXRole.row }
        var chatRooms: [ChatRoom] = []

        for row in rows.dropFirst(offset).prefix(limit) {
            guard let cell = row.children.first else { continue }

            let cellChildren = cell.children
            guard cellChildren.count >= 2 else { continue }

            var name: String?
            var time: String?
            var memberCount: Int?
            var unreadCount: Int?

            // child[0]은 항상 프로필 이미지이므로 건너뜀
            for i in 1 ..< cellChildren.count {
                let child = cellChildren[i]
                guard let value = child.stringValue, !value.isEmpty else {
                    continue
                }

                let identifier = child.attributeOrNil("AXIdentifier", as: String.self)
                switch identifier {
                case "_NS:40":
                    name = value
                case "Count Label":
                    memberCount = Int(value)
                case "_NS:69":
                    time = value
                case "", nil:
                    if unreadCount == nil, let num = Int(value) {
                        unreadCount = num
                    }
                default:
                    break
                }
            }

            if let chatName = name {
                chatRooms.append(ChatRoom(
                    name: chatName,
                    time: time,
                    memberCount: memberCount,
                    unreadCount: unreadCount,
                ))
            }
        }

        return chatRooms
    }

    static func openChat(name: String) throws {
        try goToChatsTab()

        let mainWindow = try getMainWindow()
        let table = try findChatTable(in: mainWindow)

        let rows = table.attributeOrNil("AXRows", as: [AXElement].self) ?? table.children
            .filter { $0.role == AXRole.row }

        for row in rows {
            guard let cell = row.children.first(where: { $0.role == AXRole.cell }) else { continue }

            for child in cell.children {
                let (role, stringValue) = child.attributes(.role, .stringValue)
                guard role == AXRole.staticText, let value = stringValue,
                      value.contains(name) else { continue }

                try row.setAttribute(kAXSelectedAttribute as String, value: true as CFBoolean)
                Thread.sleep(forTimeInterval: 0.1)

                let pid = try getKatokPid()
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false)
                keyDown?.postToPid(pid)
                keyUp?.postToPid(pid)

                Thread.sleep(forTimeInterval: 0.5)
                return
            }
        }

        throw CLIError.chatNotFound(name)
    }

    // MARK: - Chat Window

    static func getChatWindow(name: String) throws -> AXElement {
        let app = try getApp()
        // title과 identifier를 배치로 읽어 IPC 호출 절반으로 줄임
        let windowAttrs = app.windows.map { ($0, $0.attributes(.title, .identifier)) }

        if let (window, _) = windowAttrs
            .first(where: { $0.1.0 == name && $0.1.1 != "Main Window" })
        {
            return window
        }

        if let (window, _) = windowAttrs.first(where: {
            ($0.1.0 ?? "").contains(name) && $0.1.1 != "Main Window"
        }) {
            return window
        }

        throw CLIError.chatWindowNotOpen(name)
    }

    static func getOrOpenChatWindow(name: String) throws -> AXElement {
        if let window = try? getChatWindow(name: name) {
            return window
        }

        try openChat(name: name)

        return try getChatWindow(name: name)
    }

    static func getMessages(
        chatName: String,
        limit: Int,
    ) throws -> (windowTitle: String, messages: [Message]) {
        let chatWindow = try getOrOpenChatWindow(name: chatName)

        guard let table = try? chatWindow.findFirst(role: AXRole.table, maxDepth: 10) else {
            throw CLIError.elementNotFound("메시지 테이블")
        }

        let rows = table.children.filter { $0.role == AXRole.row }
        var messages: [Message] = []

        let timePattern = /^(오전|오후)\s*\d{1,2}:\d{2}$/
        var lastSender: String?

        for row in rows.suffix(limit) {
            guard let cell = row.children.first(where: { $0.role == AXRole.cell }) else { continue }

            let children = cell.children

            // 단일 버튼 행(날짜 구분선 등)은 건너뜀
            if children.count == 1, children[0].role == AXRole.button {
                continue
            }

            var sender: String?
            var content: String?
            var time: String?
            var hasImage = false
            var isSystemMessage = false

            for child in children {
                let role = child.role

                switch role {
                case AXRole.staticText:
                    if let value = child.stringValue, !value.isEmpty {
                        if value.wholeMatch(of: timePattern) != nil {
                            time = value
                        } else if let match = value
                            .firstMatch(of: /(?:^|\n)((?:오전|오후)\s*\d{1,2}:\d{2})$/)
                        {
                            // "1\n오후 1:35" 같은 읽지않음+시간 조합
                            time = String(match.1)
                        } else if Int(value) != nil {
                            // 숫자만 있으면 읽지않음 카운트 → 무시
                            break
                        } else {
                            sender = value
                        }
                    }

                case AXRole.image:
                    hasImage = true

                case AXRole.textArea:
                    if let value = child.stringValue, !value.isEmpty {
                        content = value
                        let identifier = child.attributeOrNil("AXIdentifier", as: String.self)
                        if identifier == "_NS:30" {
                            isSystemMessage = true
                        }
                    }

                case AXRole.scrollArea:
                    for scrollChild in child.children {
                        if scrollChild.role == AXRole.textArea, let value = scrollChild.stringValue,
                           !value.isEmpty
                        {
                            content = value
                            break
                        }
                    }

                default:
                    break
                }
            }

            if content == nil, hasImage {
                content = "[이미지]"
            }

            if let msgContent = content {
                if isSystemMessage {
                    messages.append(Message(
                        sender: nil,
                        content: msgContent,
                        time: nil,
                        isSystemMessage: true,
                    ))
                    continue
                }

                var isMyMessage = false
                let cellX = cell.position?.x ?? 0
                let contentElement = children.first(where: { $0.role == AXRole.textArea })
                    ?? children.first(where: { $0.role == AXRole.image })

                // 프로필 버튼은 항상 셀 왼쪽 가장자리(cellX+~10)에 위치
                let hasProfileButton = children.contains { child in
                    guard child.role == AXRole.button,
                          let buttonX = child.position?.x else { return false }
                    return buttonX - cellX < 20
                }

                if hasProfileButton {
                    isMyMessage = false
                } else {
                    // 시간(오전/오후) 포함 StaticText로 위치 비교
                    let timeText = children.first { child in
                        guard child.role == AXRole.staticText,
                              let value = child.stringValue else { return false }
                        return value.contains("오전") || value.contains("오후")
                    }

                    if let timeX = timeText?.position?.x,
                       let contentX = contentElement?.position?.x
                    {
                        isMyMessage = timeX < contentX
                    } else if let contentX = contentElement?.position?.x {
                        // 시간 없으면 콘텐츠 위치로 판별 (상대: ~60px, 나: 80px+)
                        isMyMessage = contentX - cellX > 75
                    }
                }

                let finalSender: String?
                if isMyMessage {
                    finalSender = nil
                } else if let s = sender {
                    lastSender = s
                    finalSender = s
                } else {
                    finalSender = lastSender ?? "???"
                }

                messages.append(Message(
                    sender: finalSender,
                    content: msgContent,
                    time: time,
                    isSystemMessage: false,
                ))
            }
        }

        closeChatWindow(chatWindow)

        return (chatWindow.title ?? chatName, messages)
    }

    private static func closeChatWindow(_ chatWindow: AXElement) {
        if let closeButton = chatWindow.children.first(where: {
            $0.attributeOrNil("AXSubrole", as: String.self) == "AXCloseButton"
        }) {
            try? closeButton.press()
        }
    }

    static func sendMessage(chatName: String, message: String) throws -> String {
        let chatWindow = try getOrOpenChatWindow(name: chatName)

        var inputTextArea: AXElement?

        for child in chatWindow.children {
            if child.role == AXRole.scrollArea {
                let hasTable = child.children.contains { $0.role == AXRole.table }
                if !hasTable {
                    if let textArea = child.children.first(where: { $0.role == AXRole.textArea }) {
                        inputTextArea = textArea
                        break
                    }
                }
            }
        }

        guard let textArea = inputTextArea else {
            throw CLIError.elementNotFound("메시지 입력창")
        }

        try textArea.setValue(message)
        Thread.sleep(forTimeInterval: 0.1)
        try textArea.focus()
        Thread.sleep(forTimeInterval: 0.1)

        let pid = try getKatokPid()
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false)
        keyDown?.postToPid(pid)
        Thread.sleep(forTimeInterval: 0.05)
        keyUp?.postToPid(pid)

        Thread.sleep(forTimeInterval: 0.3)

        closeChatWindow(chatWindow)

        return chatWindow.title ?? chatName
    }
}
