import Foundation

/// Polygon triangulation by ear clipping with hole bridging.
///
/// The algorithm follows the well-known "earcut" design: holes are bridged into
/// the outer loop, ears are clipped using a z-order curve index to skip distant
/// reflex vertices, and three fallback passes (duplicate/collinear filtering,
/// local self-intersection curing, and polygon splitting) keep degenerate input
/// from stalling. Computation happens relative to the profile's bounds origin so
/// large coordinates keep full precision.
public enum Triangulator {
    /// Triangulates a profile. Returns the cleaned loop points (outer first, then holes,
    /// consecutive duplicates removed) and CCW triangles as index triples into them.
    public static func triangulate(_ profile: Profile2) -> (points: [Vec2], triangles: [Int]) {
        var loops: [[Vec2]] = []
        for (li, loop) in profile.loops.enumerated() {
            var pts: [Vec2] = []
            for p in loop.points where pts.last.map({ !$0.isAlmostEqual(p) }) ?? true { pts.append(p) }
            while pts.count > 1, pts[0].isAlmostEqual(pts[pts.count - 1]) { pts.removeLast() }
            if pts.count < 3 {
                if li == 0 { return ([], []) }
                continue
            }
            if li > 0 && Polygon2(pts).area <= Tolerance.area { continue }
            loops.append(pts)
        }
        guard let outer = loops.first, Polygon2(outer).area > 0 else { return ([], []) }
        var all: [Vec2] = []
        var holeStarts: [Int] = []
        for (i, l) in loops.enumerated() {
            if i > 0 { holeStarts.append(all.count) }
            all.append(contentsOf: l)
        }
        let origin = profile.outer.bounds.min
        let local = all.map { $0 - origin }
        var tris = Earcut(points: local).run(holeStarts: holeStarts)
        // Guarantee CCW output.
        for t in stride(from: 0, to: tris.count, by: 3) {
            let a = local[tris[t]], b = local[tris[t + 1]], c = local[tris[t + 2]]
            if (b - a).cross(c - a) < 0 { tris.swapAt(t + 1, t + 2) }
        }
        return (all, tris)
    }

    /// Triangulates a single simple polygon.
    public static func triangulate(_ polygon: Polygon2) -> (points: [Vec2], triangles: [Int]) {
        triangulate(Profile2(outer: polygon))
    }
}

/// Array-backed earcut implementation. Node links use -1 for "none".
private final class Earcut {
    private let px: [Double]
    private let py: [Double]
    // Node storage.
    private var vi: [Int] = []      // vertex index
    private var nx: [Double] = []
    private var ny: [Double] = []
    private var prev: [Int] = []
    private var next: [Int] = []
    private var z: [Int] = []
    private var prevZ: [Int] = []
    private var nextZ: [Int] = []
    private var steiner: [Bool] = []
    private var triangles: [Int] = []
    private var minX = 0.0, minY = 0.0, invSize = 0.0

    init(points: [Vec2]) {
        px = points.map(\.x)
        py = points.map(\.y)
        let cap = points.count * 2 + 16
        vi.reserveCapacity(cap); nx.reserveCapacity(cap); ny.reserveCapacity(cap)
        prev.reserveCapacity(cap); next.reserveCapacity(cap); z.reserveCapacity(cap)
        prevZ.reserveCapacity(cap); nextZ.reserveCapacity(cap); steiner.reserveCapacity(cap)
    }

    func run(holeStarts: [Int]) -> [Int] {
        let total = px.count
        let outerLen = holeStarts.first ?? total
        guard var outerNode = linkedList(0, outerLen, clockwise: true), next[outerNode] != prev[outerNode] else { return [] }
        if !holeStarts.isEmpty { outerNode = eliminateHoles(holeStarts, outerNode) }
        if total > 80 {
            var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
            for i in 0..<outerLen {
                x0 = min(x0, px[i]); y0 = min(y0, py[i]); x1 = max(x1, px[i]); y1 = max(y1, py[i])
            }
            minX = x0; minY = y0
            let s = max(x1 - x0, y1 - y0)
            invSize = s != 0 ? 32767 / s : 0
        }
        earcutLinked(outerNode, pass: 0)
        return triangles
    }

    // MARK: Node helpers

    private func createNode(_ i: Int, _ x: Double, _ y: Double) -> Int {
        let n = vi.count
        vi.append(i); nx.append(x); ny.append(y)
        prev.append(-1); next.append(-1); z.append(0); prevZ.append(-1); nextZ.append(-1); steiner.append(false)
        return n
    }

    private func insertNode(_ i: Int, _ last: Int?) -> Int {
        let p = createNode(i, px[i], py[i])
        if let l = last {
            next[p] = next[l]; prev[p] = l
            prev[next[l]] = p; next[l] = p
        } else {
            prev[p] = p; next[p] = p
        }
        return p
    }

    private func removeNode(_ p: Int) {
        next[prev[p]] = next[p]
        prev[next[p]] = prev[p]
        if prevZ[p] >= 0 { nextZ[prevZ[p]] = nextZ[p] }
        if nextZ[p] >= 0 { prevZ[nextZ[p]] = prevZ[p] }
    }

    private func equals(_ a: Int, _ b: Int) -> Bool { nx[a] == nx[b] && ny[a] == ny[b] }

    /// Twice the signed area with earcut's sign convention (negative for CCW turns in y-up).
    private func area(_ p: Int, _ q: Int, _ r: Int) -> Double {
        (ny[q] - ny[p]) * (nx[r] - nx[q]) - (nx[q] - nx[p]) * (ny[r] - ny[q])
    }

    private func signedArea(_ start: Int, _ end: Int) -> Double {
        var sum = 0.0
        var j = end - 1
        for i in start..<end {
            sum += (px[j] - px[i]) * (py[i] + py[j])
            j = i
        }
        return sum
    }

    private func linkedList(_ start: Int, _ end: Int, clockwise: Bool) -> Int? {
        var last: Int? = nil
        if clockwise == (signedArea(start, end) > 0) {
            for i in start..<end { last = insertNode(i, last) }
        } else {
            for i in stride(from: end - 1, through: start, by: -1) { last = insertNode(i, last) }
        }
        if let l = last, equals(l, next[l]) {
            removeNode(l)
            last = next[l]
        }
        return last
    }

    private func filterPoints(_ start: Int, _ endIn: Int? = nil) -> Int {
        var end = endIn ?? start
        var p = start
        var again: Bool
        repeat {
            again = false
            if !steiner[p] && (equals(p, next[p]) || area(prev[p], p, next[p]) == 0) {
                removeNode(p)
                p = prev[p]
                end = p
                if p == next[p] { break }
                again = true
            } else {
                p = next[p]
            }
        } while again || p != end
        return end
    }

    // MARK: Main loop

    private func earcutLinked(_ earIn: Int, pass: Int) {
        var ear = earIn
        if pass == 0 && invSize != 0 { indexCurve(ear) }
        var stop = ear
        while prev[ear] != next[ear] {
            let pv = prev[ear], nv = next[ear]
            if invSize != 0 ? isEarHashed(ear) : isEar(ear) {
                triangles.append(vi[pv]); triangles.append(vi[ear]); triangles.append(vi[nv])
                removeNode(ear)
                ear = next[nv]
                stop = next[nv]
                continue
            }
            ear = nv
            if ear == stop {
                if pass == 0 {
                    earcutLinked(filterPoints(ear), pass: 1)
                } else if pass == 1 {
                    let e = cureLocalIntersections(filterPoints(ear))
                    earcutLinked(e, pass: 2)
                } else if pass == 2 {
                    splitEarcut(ear)
                }
                break
            }
        }
    }

    private func pointInTriangle(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                                 _ cx: Double, _ cy: Double, _ qx: Double, _ qy: Double) -> Bool {
        (cx - qx) * (ay - qy) >= (ax - qx) * (cy - qy)
            && (ax - qx) * (by - qy) >= (bx - qx) * (ay - qy)
            && (bx - qx) * (cy - qy) >= (cx - qx) * (by - qy)
    }

    private func pointInTriangleExceptFirst(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                                            _ cx: Double, _ cy: Double, _ qx: Double, _ qy: Double) -> Bool {
        !(ax == qx && ay == qy) && pointInTriangle(ax, ay, bx, by, cx, cy, qx, qy)
    }

    private func isEar(_ ear: Int) -> Bool {
        let a = prev[ear], b = ear, c = next[ear]
        if area(a, b, c) >= 0 { return false }
        let ax = nx[a], bx = nx[b], cx = nx[c], ay = ny[a], by = ny[b], cy = ny[c]
        let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)
        var p = next[c]
        while p != a {
            if nx[p] >= x0 && nx[p] <= x1 && ny[p] >= y0 && ny[p] <= y1
                && pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, nx[p], ny[p])
                && area(prev[p], p, next[p]) >= 0 { return false }
            p = next[p]
        }
        return true
    }

    private func isEarHashed(_ ear: Int) -> Bool {
        let a = prev[ear], b = ear, c = next[ear]
        if area(a, b, c) >= 0 { return false }
        let ax = nx[a], bx = nx[b], cx = nx[c], ay = ny[a], by = ny[b], cy = ny[c]
        let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)
        let minZ = zOrder(x0, y0), maxZ = zOrder(x1, y1)
        func blocks(_ q: Int) -> Bool {
            nx[q] >= x0 && nx[q] <= x1 && ny[q] >= y0 && ny[q] <= y1 && q != a && q != c
                && pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, nx[q], ny[q])
                && area(prev[q], q, next[q]) >= 0
        }
        var p = prevZ[ear], n = nextZ[ear]
        while p >= 0 && z[p] >= minZ && n >= 0 && z[n] <= maxZ {
            if blocks(p) { return false }
            p = prevZ[p]
            if blocks(n) { return false }
            n = nextZ[n]
        }
        while p >= 0 && z[p] >= minZ {
            if blocks(p) { return false }
            p = prevZ[p]
        }
        while n >= 0 && z[n] <= maxZ {
            if blocks(n) { return false }
            n = nextZ[n]
        }
        return true
    }

    private func cureLocalIntersections(_ startIn: Int) -> Int {
        var start = startIn
        var p = start
        repeat {
            let a = prev[p], b = next[next[p]]
            if !equals(a, b) && intersects(a, p, next[p], b) && locallyInside(a, b) && locallyInside(b, a) {
                triangles.append(vi[a]); triangles.append(vi[p]); triangles.append(vi[b])
                removeNode(p)
                removeNode(next[p])
                p = b
                start = b
            }
            p = next[p]
        } while p != start
        return filterPoints(p)
    }

    private func splitEarcut(_ start: Int) {
        var a = start
        repeat {
            var b = next[next[a]]
            while b != prev[a] {
                if vi[a] != vi[b] && isValidDiagonal(a, b) {
                    var c = splitPolygon(a, b)
                    a = filterPoints(a, next[a])
                    c = filterPoints(c, next[c])
                    earcutLinked(a, pass: 0)
                    earcutLinked(c, pass: 0)
                    return
                }
                b = next[b]
            }
            a = next[a]
        } while a != start
    }

    // MARK: Holes

    private func eliminateHoles(_ holeStarts: [Int], _ outerIn: Int) -> Int {
        var outerNode = outerIn
        var queue: [Int] = []
        for (i, s) in holeStarts.enumerated() {
            let e = i < holeStarts.count - 1 ? holeStarts[i + 1] : px.count
            guard let list = linkedList(s, e, clockwise: false) else { continue }
            if list == next[list] { steiner[list] = true }
            queue.append(getLeftmost(list))
        }
        queue.sort { a, b in
            if nx[a] != nx[b] { return nx[a] < nx[b] }
            if ny[a] != ny[b] { return ny[a] < ny[b] }
            // Tie-break by slope of the outgoing edge for determinism.
            let sa = (ny[next[a]] - ny[a]) / (nx[next[a]] - nx[a])
            let sb = (ny[next[b]] - ny[b]) / (nx[next[b]] - nx[b])
            return sa < sb
        }
        for h in queue { outerNode = eliminateHole(h, outerNode) }
        return outerNode
    }

    private func eliminateHole(_ hole: Int, _ outerNode: Int) -> Int {
        guard let bridge = findHoleBridge(hole, outerNode) else { return outerNode }
        let bridgeReverse = splitPolygon(bridge, hole)
        _ = filterPoints(bridgeReverse, next[bridgeReverse])
        return filterPoints(bridge, next[bridge])
    }

    private func findHoleBridge(_ hole: Int, _ outerNode: Int) -> Int? {
        var p = outerNode
        let hx = nx[hole], hy = ny[hole]
        var qx = -Double.infinity
        var m: Int? = nil
        if equals(hole, p) { return p }
        repeat {
            let q = next[p]
            if equals(hole, q) { return q }
            if hy <= ny[p] && hy >= ny[q] && ny[q] != ny[p] {
                let x = nx[p] + (hy - ny[p]) * (nx[q] - nx[p]) / (ny[q] - ny[p])
                if x <= hx && x > qx {
                    qx = x
                    m = nx[p] < nx[q] ? p : q
                    if x == hx { return m }
                }
            }
            p = next[p]
        } while p != outerNode
        guard var mm = m else { return nil }
        let stop = mm
        let mx = nx[mm], my = ny[mm]
        var tanMin = Double.infinity
        p = mm
        repeat {
            if hx >= nx[p] && nx[p] >= mx && hx != nx[p]
                && pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, nx[p], ny[p]) {
                let tn = abs(hy - ny[p]) / (hx - nx[p])
                if locallyInside(p, hole)
                    && (tn < tanMin || (tn == tanMin && (nx[p] > nx[mm] || (nx[p] == nx[mm] && sectorContainsSector(mm, p))))) {
                    mm = p
                    tanMin = tn
                }
            }
            p = next[p]
        } while p != stop
        return mm
    }

    private func sectorContainsSector(_ m: Int, _ p: Int) -> Bool {
        area(prev[m], m, prev[p]) < 0 && area(next[p], m, next[m]) < 0
    }

    private func getLeftmost(_ start: Int) -> Int {
        var p = start, leftmost = start
        repeat {
            if nx[p] < nx[leftmost] || (nx[p] == nx[leftmost] && ny[p] < ny[leftmost]) { leftmost = p }
            p = next[p]
        } while p != start
        return leftmost
    }

    // MARK: Diagonals

    private func isValidDiagonal(_ a: Int, _ b: Int) -> Bool {
        guard vi[next[a]] != vi[b], vi[prev[a]] != vi[b], !intersectsPolygon(a, b) else { return false }
        let visible = locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b)
            && (area(prev[a], a, prev[b]) != 0 || area(a, prev[b], b) != 0)
        let zeroLength = equals(a, b) && area(prev[a], a, next[a]) > 0 && area(prev[b], b, next[b]) > 0
        return visible || zeroLength
    }

    private func sign(_ v: Double) -> Int { v > 0 ? 1 : (v < 0 ? -1 : 0) }

    private func onSegment(_ p: Int, _ q: Int, _ r: Int) -> Bool {
        nx[q] <= max(nx[p], nx[r]) && nx[q] >= min(nx[p], nx[r]) && ny[q] <= max(ny[p], ny[r]) && ny[q] >= min(ny[p], ny[r])
    }

    private func intersects(_ p1: Int, _ q1: Int, _ p2: Int, _ q2: Int) -> Bool {
        let o1 = sign(area(p1, q1, p2)), o2 = sign(area(p1, q1, q2))
        let o3 = sign(area(p2, q2, p1)), o4 = sign(area(p2, q2, q1))
        if o1 != o2 && o3 != o4 { return true }
        if o1 == 0 && onSegment(p1, p2, q1) { return true }
        if o2 == 0 && onSegment(p1, q2, q1) { return true }
        if o3 == 0 && onSegment(p2, p1, q2) { return true }
        if o4 == 0 && onSegment(p2, q1, q2) { return true }
        return false
    }

    private func intersectsPolygon(_ a: Int, _ b: Int) -> Bool {
        var p = a
        repeat {
            let q = next[p]
            if vi[p] != vi[a] && vi[q] != vi[a] && vi[p] != vi[b] && vi[q] != vi[b] && intersects(p, q, a, b) { return true }
            p = q
        } while p != a
        return false
    }

    private func locallyInside(_ a: Int, _ b: Int) -> Bool {
        area(prev[a], a, next[a]) < 0
            ? area(a, b, next[a]) >= 0 && area(a, prev[a], b) >= 0
            : area(a, b, prev[a]) < 0 || area(a, next[a], b) < 0
    }

    private func middleInside(_ a: Int, _ b: Int) -> Bool {
        var p = a
        var inside = false
        let mx = (nx[a] + nx[b]) / 2, my = (ny[a] + ny[b]) / 2
        repeat {
            let q = next[p]
            if (ny[p] > my) != (ny[q] > my) && ny[q] != ny[p]
                && mx < (nx[q] - nx[p]) * (my - ny[p]) / (ny[q] - ny[p]) + nx[p] { inside.toggle() }
            p = q
        } while p != a
        return inside
    }

    private func splitPolygon(_ a: Int, _ b: Int) -> Int {
        let a2 = createNode(vi[a], nx[a], ny[a])
        let b2 = createNode(vi[b], nx[b], ny[b])
        let an = next[a], bp = prev[b]
        next[a] = b; prev[b] = a
        next[a2] = an; prev[an] = a2
        next[b2] = a2; prev[a2] = b2
        next[bp] = b2; prev[b2] = bp
        return b2
    }

    // MARK: Z-order

    private func zOrder(_ x: Double, _ y: Double) -> Int {
        var ix = Int(((x - minX) * invSize).rounded(.towardZero)) & 0xFFFF
        var iy = Int(((y - minY) * invSize).rounded(.towardZero)) & 0xFFFF
        ix = (ix | (ix << 8)) & 0x00FF00FF
        ix = (ix | (ix << 4)) & 0x0F0F0F0F
        ix = (ix | (ix << 2)) & 0x33333333
        ix = (ix | (ix << 1)) & 0x55555555
        iy = (iy | (iy << 8)) & 0x00FF00FF
        iy = (iy | (iy << 4)) & 0x0F0F0F0F
        iy = (iy | (iy << 2)) & 0x33333333
        iy = (iy | (iy << 1)) & 0x55555555
        return ix | (iy << 1)
    }

    private func indexCurve(_ start: Int) {
        var p = start
        repeat {
            if z[p] == 0 { z[p] = zOrder(nx[p], ny[p]) }
            prevZ[p] = prev[p]
            nextZ[p] = next[p]
            p = next[p]
        } while p != start
        nextZ[prevZ[p]] = -1
        prevZ[p] = -1
        sortLinked(p)
    }

    private func sortLinked(_ listIn: Int) {
        var list = listIn
        var inSize = 1
        var numMerges: Int
        repeat {
            var p = list
            list = -1
            var tail = -1
            numMerges = 0
            while p >= 0 {
                numMerges += 1
                var q = p
                var pSize = 0
                for _ in 0..<inSize {
                    pSize += 1
                    q = nextZ[q]
                    if q < 0 { break }
                }
                var qSize = inSize
                while pSize > 0 || (qSize > 0 && q >= 0) {
                    let e: Int
                    if pSize != 0 && (qSize == 0 || q < 0 || z[p] <= z[q]) {
                        e = p; p = nextZ[p]; pSize -= 1
                    } else {
                        e = q; q = nextZ[q]; qSize -= 1
                    }
                    if tail >= 0 { nextZ[tail] = e } else { list = e }
                    prevZ[e] = tail
                    tail = e
                }
                p = q
            }
            nextZ[tail] = -1
            inSize *= 2
        } while numMerges > 1
    }
}
