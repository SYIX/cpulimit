import Foundation

enum ProcessLister {
    // 用 ps 列出当前用户进程 (pid + 命令路径),只在面板打开/手动刷新时调用
    static func listUserProcesses() -> [UserProcess] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-u", String(getuid()), "-o", "pid=,comm="]
        let stdout = Pipe()
        ps.standardOutput = stdout
        ps.standardError = Pipe()
        do {
            try ps.run()
        } catch {
            return []
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        let selfPid = ProcessInfo.processInfo.processIdentifier
        var result: [UserProcess] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[..<space]) else { continue }
            if pid == selfPid { continue }
            let command = trimmed[trimmed.index(after: space)...]
                .trimmingCharacters(in: .whitespaces)
            let name = (command as NSString).lastPathComponent
            result.append(UserProcess(pid: pid, name: name))
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
