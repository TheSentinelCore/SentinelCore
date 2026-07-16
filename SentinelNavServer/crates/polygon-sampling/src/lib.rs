//! Bridson's Poisson Disk Sampling for polygon exploration.
//!
//! This module implements Bridson's algorithm to generate uniformly distributed
//! points within a polygon area. Useful for systematic area coverage like
//! patrolling or exploration.

use rand::Rng;

/// Configuration for polygon sampling.
#[derive(Debug, Clone)]
pub struct SamplingConfig {
    /// Minimum distance between any two generated points.
    pub min_distance: f32,
    /// Maximum candidate points to try per active point (default 30).
    pub max_candidates: usize,
    /// Maximum total points to generate (default 2048).
    pub max_points: usize,
}

impl Default for SamplingConfig {
    fn default() -> Self {
        Self {
            min_distance: 30.0,
            max_candidates: 30,
            max_points: 2048,
        }
    }
}

impl SamplingConfig {
    /// Create a new config with specified minimum distance.
    pub fn with_min_distance(min_distance: f32) -> Self {
        Self {
            min_distance,
            ..Default::default()
        }
    }
}

/// A 2D point for polygon operations.
#[derive(Debug, Clone, Copy)]
struct Point2D {
    x: f32,
    y: f32,
}

/// Generate exploration points using Bridson's Poisson Disk Sampling algorithm.
///
/// # Arguments
/// * `polygon` - Polygon vertices as (x, y, z) tuples. Z is preserved for output.
/// * `config` - Sampling configuration.
///
/// # Returns
/// Vector of points as (x, y, z) tuples, where z is the average z of the polygon.
pub fn bridson_sampling(polygon: &[[f32; 3]], config: &SamplingConfig) -> Vec<[f32; 3]> {
    if polygon.len() < 3 || config.min_distance <= 0.0 {
        return Vec::new();
    }

    let mut rng = rand::thread_rng();

    // Calculate bounding box and average Z
    let (min_x, max_x, min_y, max_y, avg_z) = calculate_bounds(polygon);

    // Convert to 2D polygon for processing
    let polygon_2d: Vec<Point2D> = polygon
        .iter()
        .map(|p| Point2D { x: p[0], y: p[1] })
        .collect();

    // Grid cell size for spatial hashing (r/sqrt(2) ensures at most one point per cell)
    let cell_size = config.min_distance / std::f32::consts::SQRT_2;
    let grid_width = ((max_x - min_x) / cell_size).ceil() as usize + 1;
    let grid_height = ((max_y - min_y) / cell_size).ceil() as usize + 1;

    // Grid stores index into points array (None = empty cell)
    let mut grid: Vec<Option<usize>> = vec![None; grid_width * grid_height];

    // Active list and final points
    let mut points: Vec<Point2D> = Vec::new();
    let mut active: Vec<usize> = Vec::new();

    // 1. Find a random starting point inside the polygon
    if let Some(start) = random_point_in_polygon(&polygon_2d, min_x, max_x, min_y, max_y, &mut rng) {
        let idx = grid_index(start.x, start.y, min_x, min_y, cell_size, grid_width);
        if idx < grid.len() {
            grid[idx] = Some(0);
            points.push(start);
            active.push(0);
        }
    } else {
        return Vec::new(); // Failed to find starting point
    }

    // 2. Main sampling loop
    while !active.is_empty() && points.len() < config.max_points {
        // Pick a random active point
        let active_idx = rng.gen_range(0..active.len());
        let point_idx = active[active_idx];
        let point = points[point_idx];

        let mut found = false;

        // Try to generate candidates around this point
        for _ in 0..config.max_candidates {
            // Generate random point in annulus [r, 2r] around active point
            let angle = rng.gen_range(0.0..std::f32::consts::TAU);
            let distance = rng.gen_range(config.min_distance..2.0 * config.min_distance);

            let candidate = Point2D {
                x: point.x + distance * angle.cos(),
                y: point.y + distance * angle.sin(),
            };

            // Check if within bounding box
            if candidate.x < min_x || candidate.x > max_x
               || candidate.y < min_y || candidate.y > max_y {
                continue;
            }

            // Check if inside polygon
            if !is_inside_polygon(candidate, &polygon_2d) {
                continue;
            }

            // Check if satisfies minimum distance constraint
            let cell_x = ((candidate.x - min_x) / cell_size) as usize;
            let cell_y = ((candidate.y - min_y) / cell_size) as usize;

            if check_neighbors(
                &grid,
                &points,
                candidate,
                cell_x,
                cell_y,
                grid_width,
                grid_height,
                config.min_distance,
            ) {
                // Valid point - add it
                let new_idx = points.len();
                let grid_idx = cell_y * grid_width + cell_x;
                if grid_idx < grid.len() {
                    grid[grid_idx] = Some(new_idx);
                    points.push(candidate);
                    active.push(new_idx);
                    found = true;
                    break;
                }
            }
        }

        if !found {
            // No valid candidate found - remove from active set
            active.swap_remove(active_idx);
        }
    }

    // Convert back to 3D points with average Z
    points
        .iter()
        .map(|p| [p.x, p.y, avg_z])
        .collect()
}

/// Calculate bounding box and average Z of polygon.
fn calculate_bounds(polygon: &[[f32; 3]]) -> (f32, f32, f32, f32, f32) {
    let mut min_x = f32::MAX;
    let mut max_x = f32::MIN;
    let mut min_y = f32::MAX;
    let mut max_y = f32::MIN;
    let mut sum_z = 0.0;

    for v in polygon {
        min_x = min_x.min(v[0]);
        max_x = max_x.max(v[0]);
        min_y = min_y.min(v[1]);
        max_y = max_y.max(v[1]);
        sum_z += v[2];
    }

    let avg_z = sum_z / polygon.len() as f32;
    (min_x, max_x, min_y, max_y, avg_z)
}

/// Calculate grid index for a point.
fn grid_index(x: f32, y: f32, min_x: f32, min_y: f32, cell_size: f32, width: usize) -> usize {
    let cell_x = ((x - min_x) / cell_size) as usize;
    let cell_y = ((y - min_y) / cell_size) as usize;
    cell_y * width + cell_x
}

/// Find a random point inside the polygon using rejection sampling.
fn random_point_in_polygon(
    polygon: &[Point2D],
    min_x: f32,
    max_x: f32,
    min_y: f32,
    max_y: f32,
    rng: &mut impl Rng,
) -> Option<Point2D> {
    // Try up to 1000 times to find a point inside
    for _ in 0..1000 {
        let candidate = Point2D {
            x: rng.gen_range(min_x..max_x),
            y: rng.gen_range(min_y..max_y),
        };

        if is_inside_polygon(candidate, polygon) {
            return Some(candidate);
        }
    }

    None
}

/// Check if a point is inside a polygon using ray-casting algorithm.
fn is_inside_polygon(point: Point2D, polygon: &[Point2D]) -> bool {
    let mut inside = false;
    let n = polygon.len();

    let mut j = n - 1;
    for i in 0..n {
        let vi = polygon[i];
        let vj = polygon[j];

        if ((vi.y > point.y) != (vj.y > point.y))
            && (point.x < (vj.x - vi.x) * (point.y - vi.y) / (vj.y - vi.y) + vi.x)
        {
            inside = !inside;
        }
        j = i;
    }

    inside
}

/// Check minimum distance to neighbors in grid cells.
fn check_neighbors(
    grid: &[Option<usize>],
    points: &[Point2D],
    candidate: Point2D,
    cell_x: usize,
    cell_y: usize,
    grid_width: usize,
    grid_height: usize,
    min_distance: f32,
) -> bool {
    let min_dist_sq = min_distance * min_distance;

    // Check 5x5 neighborhood around the cell
    for dy in 0..5i32 {
        for dx in 0..5i32 {
            let nx = cell_x as i32 + dx - 2;
            let ny = cell_y as i32 + dy - 2;

            if nx < 0 || ny < 0 || nx >= grid_width as i32 || ny >= grid_height as i32 {
                continue;
            }

            let idx = (ny as usize) * grid_width + (nx as usize);
            if let Some(point_idx) = grid.get(idx).copied().flatten() {
                let other = points[point_idx];
                let dx = candidate.x - other.x;
                let dy = candidate.y - other.y;
                if dx * dx + dy * dy < min_dist_sq {
                    return false;
                }
            }
        }
    }

    true
}

/// Order points using the Nearest Neighbor TSP heuristic.
///
/// This algorithm starts from the specified starting point and greedily
/// visits the nearest unvisited point until all points are covered.
/// While not optimal, it provides a good approximation for exploration
/// paths in reasonable time O(n²).
///
/// # Arguments
/// * `points` - Points to order as (x, y, z) arrays
/// * `start` - Starting point (x, y, z) - the first point in the result
///
/// # Returns
/// Ordered points starting from the point nearest to `start`, visiting each point once.
pub fn nearest_neighbor_tsp(points: &[[f32; 3]], start: [f32; 3]) -> Vec<[f32; 3]> {
    if points.is_empty() {
        return Vec::new();
    }

    if points.len() == 1 {
        return vec![points[0]];
    }

    // Find the point closest to the start position
    let mut visited = vec![false; points.len()];
    let mut result = Vec::with_capacity(points.len());

    // Find initial point closest to start
    let mut current_idx = 0;
    let mut min_dist = f32::MAX;
    for (i, p) in points.iter().enumerate() {
        let d = distance_2d(start, *p);
        if d < min_dist {
            min_dist = d;
            current_idx = i;
        }
    }

    // Add first point
    visited[current_idx] = true;
    result.push(points[current_idx]);

    // Greedy nearest neighbor
    while result.len() < points.len() {
        let current = result[result.len() - 1];
        let mut nearest_idx = None;
        let mut nearest_dist = f32::MAX;

        for (i, p) in points.iter().enumerate() {
            if !visited[i] {
                let d = distance_2d(current, *p);
                if d < nearest_dist {
                    nearest_dist = d;
                    nearest_idx = Some(i);
                }
            }
        }

        if let Some(idx) = nearest_idx {
            visited[idx] = true;
            result.push(points[idx]);
        } else {
            break; // No more unvisited points
        }
    }

    result
}

/// Calculate 2D distance between two 3D points (ignoring Z).
/// For TSP ordering, we use 2D distance as the player walks on a surface.
fn distance_2d(a: [f32; 3], b: [f32; 3]) -> f32 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    (dx * dx + dy * dy).sqrt()
}

/// Generate exploration points with TSP ordering.
///
/// This is a convenience function that combines Bridson sampling with
/// nearest-neighbor TSP ordering. The result is a set of uniformly
/// distributed points ordered for efficient traversal.
///
/// # Arguments
/// * `polygon` - Polygon vertices as (x, y, z) tuples
/// * `config` - Sampling configuration
/// * `start` - Starting position for TSP ordering
///
/// # Returns
/// Vector of points ordered for efficient traversal starting near `start`.
pub fn bridson_sampling_with_tsp(
    polygon: &[[f32; 3]],
    config: &SamplingConfig,
    start: [f32; 3],
) -> Vec<[f32; 3]> {
    let samples = bridson_sampling(polygon, config);
    if samples.is_empty() {
        return samples;
    }
    nearest_neighbor_tsp(&samples, start)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_polygon() {
        let polygon: Vec<[f32; 3]> = vec![];
        let config = SamplingConfig::default();
        let points = bridson_sampling(&polygon, &config);
        assert!(points.is_empty());
    }

    #[test]
    fn test_too_few_vertices() {
        let polygon = vec![[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]]; // Only 2 vertices
        let config = SamplingConfig::default();
        let points = bridson_sampling(&polygon, &config);
        assert!(points.is_empty());
    }

    #[test]
    fn test_simple_square() {
        // 100x100 square at Z=50
        let polygon = vec![
            [0.0, 0.0, 50.0],
            [100.0, 0.0, 50.0],
            [100.0, 100.0, 50.0],
            [0.0, 100.0, 50.0],
        ];
        let config = SamplingConfig::with_min_distance(20.0);
        let points = bridson_sampling(&polygon, &config);

        // Should generate some points
        assert!(!points.is_empty());

        // All points should have Z=50
        for p in &points {
            assert!((p[2] - 50.0).abs() < 0.001);
        }
    }

    #[test]
    fn test_min_distance_constraint() {
        let polygon = vec![
            [0.0, 0.0, 0.0],
            [100.0, 0.0, 0.0],
            [100.0, 100.0, 0.0],
            [0.0, 100.0, 0.0],
        ];
        let min_dist = 15.0;
        let config = SamplingConfig::with_min_distance(min_dist);
        let points = bridson_sampling(&polygon, &config);

        // Check that all points are at least min_distance apart
        for i in 0..points.len() {
            for j in (i + 1)..points.len() {
                let dx = points[i][0] - points[j][0];
                let dy = points[i][1] - points[j][1];
                let dist = (dx * dx + dy * dy).sqrt();
                assert!(
                    dist >= min_dist * 0.99, // Allow tiny floating point error
                    "Points too close: {} < {}",
                    dist,
                    min_dist
                );
            }
        }
    }

    #[test]
    fn test_all_points_inside_polygon() {
        let polygon = vec![
            [0.0, 0.0, 0.0],
            [50.0, 0.0, 0.0],
            [50.0, 50.0, 0.0],
            [0.0, 50.0, 0.0],
        ];
        let config = SamplingConfig::with_min_distance(10.0);
        let points = bridson_sampling(&polygon, &config);

        let polygon_2d: Vec<Point2D> = polygon
            .iter()
            .map(|p| Point2D { x: p[0], y: p[1] })
            .collect();

        for p in &points {
            let point = Point2D { x: p[0], y: p[1] };
            assert!(
                is_inside_polygon(point, &polygon_2d),
                "Point ({}, {}) outside polygon",
                p[0],
                p[1]
            );
        }
    }

    #[test]
    fn test_is_inside_polygon() {
        let square = vec![
            Point2D { x: 0.0, y: 0.0 },
            Point2D { x: 10.0, y: 0.0 },
            Point2D { x: 10.0, y: 10.0 },
            Point2D { x: 0.0, y: 10.0 },
        ];

        // Inside
        assert!(is_inside_polygon(Point2D { x: 5.0, y: 5.0 }, &square));
        assert!(is_inside_polygon(Point2D { x: 1.0, y: 1.0 }, &square));
        assert!(is_inside_polygon(Point2D { x: 9.0, y: 9.0 }, &square));

        // Outside
        assert!(!is_inside_polygon(Point2D { x: -1.0, y: 5.0 }, &square));
        assert!(!is_inside_polygon(Point2D { x: 11.0, y: 5.0 }, &square));
        assert!(!is_inside_polygon(Point2D { x: 5.0, y: -1.0 }, &square));
        assert!(!is_inside_polygon(Point2D { x: 5.0, y: 11.0 }, &square));
    }

    #[test]
    fn test_triangle_polygon() {
        let triangle = vec![
            [0.0, 0.0, 10.0],
            [100.0, 0.0, 10.0],
            [50.0, 86.6, 10.0], // Equilateral triangle
        ];
        let config = SamplingConfig::with_min_distance(15.0);
        let points = bridson_sampling(&triangle, &config);

        assert!(!points.is_empty());
        // All Z values should be 10
        for p in &points {
            assert!((p[2] - 10.0).abs() < 0.001);
        }
    }

    #[test]
    fn test_invalid_min_distance() {
        let polygon = vec![
            [0.0, 0.0, 0.0],
            [100.0, 0.0, 0.0],
            [100.0, 100.0, 0.0],
            [0.0, 100.0, 0.0],
        ];

        // Zero min_distance should return empty
        let config = SamplingConfig {
            min_distance: 0.0,
            ..Default::default()
        };
        assert!(bridson_sampling(&polygon, &config).is_empty());

        // Negative min_distance should return empty
        let config = SamplingConfig {
            min_distance: -5.0,
            ..Default::default()
        };
        assert!(bridson_sampling(&polygon, &config).is_empty());
    }

    #[test]
    fn test_nearest_neighbor_tsp_empty() {
        let points: Vec<[f32; 3]> = vec![];
        let result = nearest_neighbor_tsp(&points, [0.0, 0.0, 0.0]);
        assert!(result.is_empty());
    }

    #[test]
    fn test_nearest_neighbor_tsp_single() {
        let points = vec![[10.0, 20.0, 5.0]];
        let result = nearest_neighbor_tsp(&points, [0.0, 0.0, 0.0]);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0], [10.0, 20.0, 5.0]);
    }

    #[test]
    fn test_nearest_neighbor_tsp_ordering() {
        // Points arranged in a line: start should go to nearest first
        let points = vec![
            [100.0, 0.0, 0.0],  // Furthest from start
            [50.0, 0.0, 0.0],   // Middle
            [10.0, 0.0, 0.0],   // Closest to start
        ];
        let start = [0.0, 0.0, 0.0];
        let result = nearest_neighbor_tsp(&points, start);

        // Should visit in order: closest first
        assert_eq!(result.len(), 3);
        assert_eq!(result[0], [10.0, 0.0, 0.0]);   // Closest first
        assert_eq!(result[1], [50.0, 0.0, 0.0]);   // Then middle
        assert_eq!(result[2], [100.0, 0.0, 0.0]);  // Then furthest
    }

    #[test]
    fn test_nearest_neighbor_tsp_visits_all() {
        let points = vec![
            [0.0, 0.0, 0.0],
            [10.0, 0.0, 0.0],
            [5.0, 10.0, 0.0],
            [15.0, 5.0, 0.0],
            [20.0, 10.0, 0.0],
        ];
        let start = [0.0, 0.0, 0.0];
        let result = nearest_neighbor_tsp(&points, start);

        // All points should be visited
        assert_eq!(result.len(), points.len());

        // Each original point should appear exactly once
        for p in &points {
            let count = result.iter().filter(|r| *r == p).count();
            assert_eq!(count, 1, "Point {:?} not visited exactly once", p);
        }
    }

    #[test]
    fn test_nearest_neighbor_tsp_2d_distance() {
        // Z coordinate shouldn't affect ordering
        let points = vec![
            [100.0, 0.0, 1000.0],  // High Z but far XY
            [10.0, 0.0, -1000.0],  // Low Z but close XY
        ];
        let start = [0.0, 0.0, 0.0];
        let result = nearest_neighbor_tsp(&points, start);

        // Should visit [10, 0] first because it's closer in 2D
        assert_eq!(result[0], [10.0, 0.0, -1000.0]);
    }

    #[test]
    fn test_bridson_sampling_with_tsp() {
        let polygon = vec![
            [0.0, 0.0, 50.0],
            [100.0, 0.0, 50.0],
            [100.0, 100.0, 50.0],
            [0.0, 100.0, 50.0],
        ];
        let config = SamplingConfig::with_min_distance(20.0);
        let start = [0.0, 0.0, 50.0];

        let result = bridson_sampling_with_tsp(&polygon, &config, start);

        // Should have points
        assert!(!result.is_empty());

        // First point should be closest to start
        let first_dist = distance_2d(result[0], start);
        for p in &result[1..] {
            let d = distance_2d(*p, start);
            assert!(
                d >= first_dist * 0.95, // Allow small floating point variance
                "First point not closest to start"
            );
        }
    }
}
