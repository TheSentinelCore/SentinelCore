//! TSP (Traveling Salesman Problem) solver using nearest-neighbor + 2-opt improvement.

/// Solve TSP using nearest-neighbor heuristic with weighted costs and 2-opt improvement.
///
/// `distances[i][j]` = distance from node i to node j.
/// `weights[j]` = importance weight for visiting node j (higher = prefer visiting earlier).
///
/// Returns the ordered sequence of node indices (starting from node 0).
pub fn solve_tsp(distances: &[Vec<f32>], weights: &[f32]) -> Vec<usize> {
    let n = distances.len();
    if n <= 2 {
        return (0..n).collect();
    }

    // --- Nearest-neighbor greedy ---
    let mut visited = vec![false; n];
    let mut order = Vec::with_capacity(n);
    let mut current = 0usize;
    visited[current] = true;
    order.push(current);

    for _ in 1..n {
        let mut best_idx = None;
        let mut best_cost = f32::MAX;

        for j in 0..n {
            if !visited[j] {
                let cost = distances[current][j] / weights[j];
                if cost < best_cost {
                    best_cost = cost;
                    best_idx = Some(j);
                }
            }
        }

        if let Some(next) = best_idx {
            visited[next] = true;
            order.push(next);
            current = next;
        }
    }

    // --- 2-opt improvement ---
    let mut improved = true;
    while improved {
        improved = false;
        for i in 1..order.len() - 1 {
            for j in (i + 1)..order.len() {
                let old_cost = distances[order[i - 1]][order[i]]
                    + distances[order[j - 1]][order[j % order.len()]];
                let new_cost = distances[order[i - 1]][order[j - 1]]
                    + distances[order[i]][order[j % order.len()]];

                if new_cost < old_cost - 0.01 {
                    order[i..j].reverse();
                    improved = true;
                }
            }
        }
    }

    order
}
