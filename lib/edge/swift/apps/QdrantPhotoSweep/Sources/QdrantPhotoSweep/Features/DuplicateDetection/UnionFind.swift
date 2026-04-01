import Foundation

struct UnionFind<Element: Hashable> {
    private var parent: [Element: Element] = [:]
    private var rank: [Element: Int] = [:]

    mutating func find(_ element: Element) -> Element {
        guard let p = parent[element] else {
            parent[element] = element
            rank[element] = 0
            return element
        }
        guard p != element else { return element }
        let root = find(p)
        parent[element] = root
        return root
    }

    mutating func union(_ a: Element, _ b: Element) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }

        let rankA = rank[rootA, default: 0]
        let rankB = rank[rootB, default: 0]

        switch rankA {
        case _ where rankA < rankB:
            parent[rootA] = rootB
        case _ where rankA > rankB:
            parent[rootB] = rootA
        default:
            parent[rootB] = rootA
            rank[rootA] = rankA + 1
        }
    }

    mutating func components() -> [[Element]] {
        var groups: [Element: [Element]] = [:]
        for element in parent.keys {
            let root = find(element)
            groups[root, default: []].append(element)
        }
        return Array(groups.values.filter { $0.count > 1 })
    }
}
