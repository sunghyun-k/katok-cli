struct Friend {
    let name: String
    let statusMessage: String?
}

struct FriendSection {
    let name: String
    let friends: [Friend]
}

struct ChatRoom {
    let name: String
    let time: String?
    let memberCount: Int?
    let unreadCount: Int?
}

struct Message {
    let sender: String?
    let content: String
    let time: String?
    let isSystemMessage: Bool
}
