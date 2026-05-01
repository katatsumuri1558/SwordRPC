//
//  RPC.swift
//  SwordRPC
//
//  Created by Alejandro Alonso
//  Copyright © 2017 Alejandro Alonso. All rights reserved.
//

import Foundation

extension SwordRPC {
    /// Sends a handshake to begin RPC interaction.
    func handshake() throws {
        let response = AuthorizationRequest(version: 1, clientId: appId)
        try send(response, opcode: .handshake)
    }

    /// Emits a subscribe request for the given command type.
    /// https://discord.com/developers/docs/topics/rpc#subscribe
    /// - Parameter type: The event type to subscribe for.
    func subscribe(_ type: EventType) {
        let command = Command(cmd: .subscribe, evt: type)
        try? send(command)
    }

    /// Handles incoming events from Discord.
    /// - Parameter payload: JSON given over IPC.
    func handleEvent(_ payload: String) {
        let data = decode(payload)

        // Known event types (READY, ERROR, ACTIVITY_*) come with `evt` set
        // to the event name. They may also have `cmd: "DISPATCH"`.
        if let evt = data["evt"] as? String, let event = EventType(rawValue: evt) {
            let eventData = (data["data"] as? [String: Any]) ?? [:]

            switch event {
            case .error:
                let code = eventData["code"] as? Int ?? 0
                let message = eventData["message"] as? String ?? ""
                delegate?.rpcDidReceiveError(self, code: code, message: message)

            case .join:
                if let secret = eventData["secret"] as? String {
                    delegate?.rpcDidJoinGame(self, secret: secret)
                }

            case .joinRequest:
                guard let user = eventData["user"] as? [String: String],
                      let secret = eventData["secret"] as? String else { return }
                let joinRequest = PartialUser(
                    avatar: user["avatar"] ?? "",
                    discriminator: user["discriminator"] ?? "",
                    userId: user["id"] ?? "",
                    username: user["username"] ?? ""
                )
                delegate?.rpcDidReceiveJoinRequest(self, user: joinRequest, secret: secret)

            case .ready:
                delegate?.rpcDidConnect(self)
                startPresenceUpdater()

            case .spectate:
                if let secret = eventData["secret"] as? String {
                    delegate?.rpcDidSpectateGame(self, secret: secret)
                }
            }
            return
        }

        // Successful command ack (e.g. SET_ACTIVITY response): `cmd` is set
        // and `evt` is null/missing. The previous implementation treated
        // these as disconnects, breaking presence updates entirely.
        if data["cmd"] != nil {
            return
        }

        // Otherwise: empty payload from channelInactive, or a close frame
        // from Discord carrying `code`/`message`.
        delegate?.rpcDidDisconnect(self, code: data["code"] as? Int, message: data["message"] as? String)
    }
}
