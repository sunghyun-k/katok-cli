import ArgumentParser

@main
struct KatokCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "katok",
        abstract: "macOS 카카오톡 자동화 CLI",
        subcommands: [Friends.self, Chats.self, Messages.self, Send.self],
        defaultSubcommand: Chats.self,
    )
}

// MARK: - Friends

extension KatokCLI {
    struct Friends: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "친구 목록 표시",
        )

        func run() throws {
            let sections = try KatokService.getFriendsSections()

            if sections.isEmpty {
                print("친구가 없습니다.")
                return
            }

            print("name,status_message")

            for section in sections {
                print("# \(section.name)")

                for friend in section.friends {
                    let name = csvEscape(friend.name)
                    let status = csvEscape(friend.statusMessage ?? "")
                    print("\(name),\(status)")
                }
            }
        }
    }
}

// MARK: - Chats

extension KatokCLI {
    struct Chats: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "채팅방 목록 표시",
        )

        @Option(name: .shortAndLong, help: "가져올 채팅방 수")
        var limit: Int = 50

        @Option(name: .shortAndLong, help: "건너뛸 채팅방 수")
        var offset: Int = 0

        func run() throws {
            let chatRooms = try KatokService.getChatList(limit: limit, offset: offset)

            if chatRooms.isEmpty {
                print("채팅방이 없습니다.")
                return
            }

            print("name,time,member_count,unread_count")

            for chat in chatRooms {
                let name = csvEscape(chat.name)
                let time = csvEscape(chat.time ?? "")
                let memberCount = "\(chat.memberCount ?? 1)명"
                let unreadCount = "\(chat.unreadCount ?? 0)"
                print("\(name),\(time),\(memberCount),\(unreadCount)")
            }
        }
    }
}

private func csvEscape(_ value: String) -> String {
    let singleLine = value.replacingOccurrences(of: "\n", with: " ")
    let needsQuotes = singleLine.contains(",") || singleLine.contains("\"")
    if needsQuotes {
        let escaped = singleLine.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return singleLine
}

// MARK: - Messages

extension KatokCLI {
    struct Messages: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "채팅방의 메시지 읽기",
        )

        @Argument(help: "채팅방 이름")
        var chatName: String

        @Option(name: .shortAndLong, help: "가져올 메시지 수")
        var limit: Int = 50

        func run() throws {
            let (_, messages) = try KatokService.getMessages(chatName: chatName, limit: limit)

            if messages.isEmpty {
                print("메시지가 없습니다.")
                return
            }

            print("sender,content,time")

            for msg in messages {
                if msg.isSystemMessage {
                    print("# \(msg.content)")
                    continue
                }

                let sender = csvEscape(msg.sender ?? "나")
                let content = csvEscape(msg.content)
                let time = csvEscape(msg.time ?? "")
                print("\(sender),\(content),\(time)")
            }
        }
    }
}

// MARK: - Send

extension KatokCLI {
    struct Send: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "메시지 보내기",
        )

        @Argument(help: "채팅방 이름")
        var chatName: String

        @Argument(help: "보낼 메시지")
        var message: String

        func run() throws {
            let title = try KatokService.sendMessage(chatName: chatName, message: message)
            print("'\(title)'에 메시지를 보냈습니다.")
        }
    }
}
