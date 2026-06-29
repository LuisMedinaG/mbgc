import Foundation

struct BGGCSVRow: Identifiable, Equatable {
    let bggId: Int
    let name: String

    var id: Int { bggId }
}

enum BGGCSVParser {
    static func parse(_ raw: String) -> [BGGCSVRow] {
        let records = csvRecords(raw).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard !records.isEmpty else { return [] }

        guard let headerIndex = records.firstIndex(where: { record in
            record.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "objectid" }
        }) else {
            return []
        }

        let headers = records[headerIndex].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let idCol = headers.firstIndex(of: "objectid") else { return [] }
        let nameCol = headers.firstIndex(of: "objectname")

        var seen: Set<Int> = []
        var rows: [BGGCSVRow] = []
        for fields in records.dropFirst(headerIndex + 1) {
            guard fields.count > idCol,
                  let id = Int(fields[idCol].trimmingCharacters(in: .whitespaces)),
                  id > 0,
                  seen.insert(id).inserted else { continue }

            let name: String
            if let nameCol, fields.count > nameCol {
                name = fields[nameCol].trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                name = "BGG #\(id)"
            }

            rows.append(BGGCSVRow(bggId: id, name: name.isEmpty ? "BGG #\(id)" : name))
        }
        return rows
    }

    private static func csvRecords(_ raw: String) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = raw.makeIterator()

        while let ch = iterator.next() {
            if ch == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        inQuotes = false
                        if next == "," {
                            fields.append(current)
                            current = ""
                        } else if next == "\n" {
                            fields.append(current)
                            records.append(fields)
                            fields = []
                            current = ""
                        } else if next != "\r" {
                            current.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else if ch == "\n" && !inQuotes {
                fields.append(current)
                records.append(fields)
                fields = []
                current = ""
            } else if ch != "\r" || inQuotes {
                current.append(ch)
            }
        }

        if !current.isEmpty || !fields.isEmpty {
            fields.append(current)
            records.append(fields)
        }
        return records
    }
}
