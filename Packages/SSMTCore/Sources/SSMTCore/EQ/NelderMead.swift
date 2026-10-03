import Foundation

/// Minimal Nelder–Mead simplex minimizer (no external dependency; 3 parameters per EQ band).
public enum NelderMead {
    public static func minimize(_ f: ([Double]) -> Double, start x0: [Double], step: [Double],
                                maxIterations: Int = 300, tolerance: Double = 1e-6) -> (x: [Double], value: Double) {
        let n = x0.count
        var simplex: [[Double]] = [x0]
        for i in 0..<n {
            var x = x0
            x[i] += step[i]
            simplex.append(x)
        }
        var values = simplex.map(f)
        for _ in 0..<maxIterations {
            let order = values.indices.sorted { values[$0] < values[$1] }
            simplex = order.map { simplex[$0] }
            values = order.map { values[$0] }
            if abs(values[n] - values[0]) <= tolerance * (abs(values[0]) + 1e-12) { break }
            var centroid = [Double](repeating: 0, count: n)
            for i in 0..<n { for j in 0..<n { centroid[j] += simplex[i][j] / Double(n) } }
            func along(_ t: Double) -> [Double] { (0..<n).map { centroid[$0] + t * (simplex[n][$0] - centroid[$0]) } }
            let xr = along(-1), fr = f(xr)
            if fr < values[0] {
                let xe = along(-2), fe = f(xe)
                if fe < fr { simplex[n] = xe; values[n] = fe } else { simplex[n] = xr; values[n] = fr }
            } else if fr < values[n - 1] {
                simplex[n] = xr; values[n] = fr
            } else {
                let xc = fr < values[n] ? along(-0.5) : along(0.5)
                let fc = f(xc)
                if fc < min(fr, values[n]) {
                    simplex[n] = xc; values[n] = fc
                } else {
                    for i in 1...n {
                        simplex[i] = (0..<n).map { simplex[0][$0] + 0.5 * (simplex[i][$0] - simplex[0][$0]) }
                        values[i] = f(simplex[i])
                    }
                }
            }
        }
        let best = values.indices.min { values[$0] < values[$1] }!
        return (simplex[best], values[best])
    }
}
