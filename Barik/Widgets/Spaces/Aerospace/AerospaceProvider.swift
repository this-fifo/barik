import Foundation

class AerospaceSpacesProvider: SpacesProvider, SwitchableSpacesProvider, FocusAwareSpacesProvider {
    typealias SpaceType = AeroSpace
    let commandRunner: AerospaceCommandRunner = .init(
        executablePath: ConfigManager.shared.config.aerospace.path)

    // Cache last known focused space/window to avoid extra queries
    private var cachedFocusedSpaceId: String?
    private var cachedFocusedWindowId: Int?

    private struct AerospaceState {
        let spaces: [AeroSpace]
        let windows: [AeroWindow]
        let focusedSpaceId: String?
        let focusedWindowId: Int?
    }

    func getSpacesWithWindows() -> [AeroSpace]? {
        guard let state = fetchState() else {
            return nil
        }
        var spaces = state.spaces
        let fallbackSpaceId = state.focusedSpaceId
            ?? spaces.first(where: { $0.isFocused }).map { $0.id }
        if let fallbackSpaceId {
            // Update cache
            cachedFocusedSpaceId = fallbackSpaceId
            for i in 0..<spaces.count {
                spaces[i].isFocused = (spaces[i].id == fallbackSpaceId)
            }
        }
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        let focusedWindowId = state.focusedWindowId
            ?? state.windows.first(where: { $0.isFocused }).map { $0.id }
        // Update cache
        if let focusedWindowId {
            cachedFocusedWindowId = focusedWindowId
        }
        for window in state.windows {
            var mutableWindow = window
            if let focusedWindowId, window.id == focusedWindowId {
                mutableWindow.isFocused = true
            }
            if let ws = mutableWindow.workspace, !ws.isEmpty {
                if var space = spaceDict[ws] {
                    space.windows.append(mutableWindow)
                    spaceDict[ws] = space
                }
            } else if let fallbackSpaceId, var space = spaceDict[fallbackSpaceId] {
                space.windows.append(mutableWindow)
                spaceDict[fallbackSpaceId] = space
            }
        }
        var resultSpaces = Array(spaceDict.values)
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort { $0.id < $1.id }
        }
        return resultSpaces.filter { !$0.windows.isEmpty }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _ = runAerospaceCommand(arguments: ["workspace", spaceId])
        // Update cache immediately after focus change
        cachedFocusedSpaceId = spaceId
    }

    func focusWindow(windowId: String) {
        _ = runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    func getFocusedSpaceId() -> String? {
        // Always fetch fresh data for polling (no cache)
        // Cache is only used in getSpacesWithWindows() for optimization
        return fetchFocusedSpace()?.id
    }

    func getFocusedWindowId() -> Int? {
        // Always fetch fresh data for polling (no cache)
        // Cache is only used in getSpacesWithWindows() for optimization
        return fetchFocusedWindow()?.id
    }

    private func runAerospaceCommand(arguments: [String]) -> Data? {
        return commandRunner.run(arguments: arguments)
    }

    private func fetchState() -> AerospaceState? {
        let group = DispatchGroup()
        var spaces: [AeroSpace]?
        var windows: [AeroWindow]?
        var focusedSpace: AeroSpace?
        var focusedWindow: AeroWindow?

        let fetchQueue = DispatchQueue(
            label: "io.barik.aerospace.fetch", attributes: .concurrent)

        // Fetch all data in parallel (4 concurrent requests)
        group.enter()
        fetchQueue.async {
            spaces = self.fetchSpaces()
            group.leave()
        }

        group.enter()
        fetchQueue.async {
            windows = self.fetchWindows()
            group.leave()
        }

        group.enter()
        fetchQueue.async {
            focusedSpace = self.fetchFocusedSpace()
            group.leave()
        }

        group.enter()
        fetchQueue.async {
            focusedWindow = self.fetchFocusedWindow()
            group.leave()
        }

        group.wait()

        guard let resolvedSpaces = spaces, let resolvedWindows = windows else {
            return nil
        }

        // Use focused queries results (--all queries don't include focus info)
        let focusedSpaceId = focusedSpace?.id
        let focusedWindowId = focusedWindow?.id

        return AerospaceState(
            spaces: resolvedSpaces,
            windows: resolvedWindows,
            focusedSpaceId: focusedSpaceId,
            focusedWindowId: focusedWindowId)
    }

    private func fetchSpaces() -> [AeroSpace]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--all", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data)
        } catch {
            print("Decode spaces error: \(error)")
            return nil
        }
    }

    private func fetchWindows() -> [AeroWindow]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{window-id} %{app-name} %{window-title} %{workspace}",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data)
        } catch {
            print("Decode windows error: \(error)")
            return nil
        }
    }

    func fetchFocusedSpace() -> AeroSpace? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data).first
        } catch {
            print("Decode focused space error: \(error)")
            return nil
        }
    }

    private func fetchFocusedWindow() -> AeroWindow? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data).first
        } catch {
            print("Decode focused window error: \(error)")
            return nil
        }
    }
}
