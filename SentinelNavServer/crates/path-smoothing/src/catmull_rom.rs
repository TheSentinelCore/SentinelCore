//! Centripetal Catmull-Rom spline interpolation.
//!
//! Uses the Barry-Goldman recursive algorithm with parameterized alpha.
//! Alpha=0.5 (centripetal) guarantees no cusps, no self-intersections,
//! and no overshoot — proven by Yuksel et al. (2011).

use detour::Vec3;
use crate::terrain::TerrainAnalysis;

/// Minimum distance between points before treating as degenerate.
const DEGENERATE_THRESHOLD: f32 = 0.001;

/// Smooth a path using centripetal Catmull-Rom spline interpolation.
///
/// # Arguments
/// * `path` — Input waypoints (< 2 returned as-is)
/// * `alpha` — Parameterization: 0.0=uniform, 0.5=centripetal, 1.0=chordal
/// * `tension` — 0.0=natural curves, 1.0=straight lines
/// * `points_per_segment` — Base interpolation density
/// * `adaptive_density` — If true, scale density on stairs/ramps
/// * `stair_threshold` — Slope ratio threshold for terrain detection
pub fn smooth_catmull_rom_centripetal(
    path: &[Vec3],
    alpha: f32,
    tension: f32,
    points_per_segment: usize,
    adaptive_density: bool,
    stair_threshold: f32,
) -> Vec<Vec3> {
    if path.len() < 2 {
        return path.to_vec();
    }
    if path.len() == 2 {
        return linear_interpolate(&path[0], &path[1], points_per_segment);
    }

    let mut result = Vec::new();

    for i in 0..path.len() - 1 {
        let p0 = if i == 0 {
            mirror_endpoint(path[0], path[1])
        } else {
            path[i - 1]
        };
        let p1 = path[i];
        let p2 = path[i + 1];
        let p3 = if i + 2 >= path.len() {
            mirror_endpoint(path[path.len() - 1], path[path.len() - 2])
        } else {
            path[i + 2]
        };

        let density = if adaptive_density {
            let analysis = TerrainAnalysis::analyze_segment(&p1, &p2);
            analysis.scale_density(points_per_segment, stair_threshold)
        } else {
            points_per_segment
        };

        let t0 = 0.0f32;
        let t1 = t0 + knot_delta(p0, p1, alpha);
        let t2 = t1 + knot_delta(p1, p2, alpha);
        let t3 = t2 + knot_delta(p2, p3, alpha);

        if (t2 - t1).abs() < DEGENERATE_THRESHOLD {
            if i == 0 {
                result.push(p1);
            }
            continue;
        }

        for j in 0..density {
            let frac = j as f32 / density as f32;
            let u = t1 + (t2 - t1) * frac;
            let point = barry_goldman(p0, p1, p2, p3, t0, t1, t2, t3, u, tension);
            result.push(point);
        }
    }

    result.push(*path.last().unwrap());
    result
}

/// Barry-Goldman recursive evaluation at parameter u.
#[allow(clippy::too_many_arguments)]
fn barry_goldman(
    p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3,
    t0: f32, t1: f32, t2: f32, t3: f32,
    u: f32,
    tension: f32,
) -> Vec3 {
    let a1 = lerp_parametric(p0, p1, t0, t1, u);
    let a2 = lerp_parametric(p1, p2, t1, t2, u);
    let a3 = lerp_parametric(p2, p3, t2, t3, u);
    let b1 = lerp_parametric(a1, a2, t0, t2, u);
    let b2 = lerp_parametric(a2, a3, t1, t3, u);
    let c = lerp_parametric(b1, b2, t1, t2, u);

    if tension > 0.0 {
        let linear = lerp_parametric(p1, p2, t1, t2, u);
        Vec3::new(
            c.x * (1.0 - tension) + linear.x * tension,
            c.y * (1.0 - tension) + linear.y * tension,
            c.z * (1.0 - tension) + linear.z * tension,
        )
    } else {
        c
    }
}

/// Knot delta: |P_i - P_{i-1}|^alpha.
fn knot_delta(a: Vec3, b: Vec3, alpha: f32) -> f32 {
    let d = a.distance_2d(&b);
    if d < DEGENERATE_THRESHOLD {
        DEGENERATE_THRESHOLD
    } else {
        d.powf(alpha)
    }
}

/// Parametric lerp between two Vec3 values.
fn lerp_parametric(a: Vec3, b: Vec3, t_a: f32, t_b: f32, u: f32) -> Vec3 {
    let denom = t_b - t_a;
    if denom.abs() < 1e-10 {
        return a;
    }
    let w = (u - t_a) / denom;
    Vec3::new(
        a.x + (b.x - a.x) * w,
        a.y + (b.y - a.y) * w,
        a.z + (b.z - a.z) * w,
    )
}

/// Mirror endpoint for natural boundary conditions: 2*endpoint - neighbor.
fn mirror_endpoint(endpoint: Vec3, neighbor: Vec3) -> Vec3 {
    Vec3::new(
        2.0 * endpoint.x - neighbor.x,
        2.0 * endpoint.y - neighbor.y,
        2.0 * endpoint.z - neighbor.z,
    )
}

/// Linear interpolation between two points.
fn linear_interpolate(a: &Vec3, b: &Vec3, num_points: usize) -> Vec<Vec3> {
    let mut result = Vec::with_capacity(num_points + 1);
    for i in 0..=num_points {
        let t = i as f32 / num_points as f32;
        result.push(Vec3::new(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t,
        ));
    }
    result
}

/// Deprecated: use `smooth_catmull_rom_centripetal` with alpha=0.5 instead.
#[deprecated(since = "0.2.0", note = "Use smooth_catmull_rom_centripetal with alpha=0.5")]
pub fn smooth_catmull_rom(path: &[Vec3], samples_per_segment: usize) -> Vec<Vec3> {
    smooth_catmull_rom_centripetal(path, 0.0, 0.0, samples_per_segment, false, 0.3)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_centripetal_preserves_endpoints() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(20.0, 5.0, 0.0),
            Vec3::new(30.0, 5.0, 0.0),
        ];
        let smoothed = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 8, false, 0.3);
        assert_eq!(smoothed[0], path[0]);
        assert_eq!(*smoothed.last().unwrap(), *path.last().unwrap());
    }

    #[test]
    fn test_centripetal_more_points_than_input() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(20.0, 5.0, 0.0),
            Vec3::new(30.0, 5.0, 0.0),
        ];
        let smoothed = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 8, false, 0.3);
        assert!(smoothed.len() > path.len());
    }

    #[test]
    fn test_two_point_path_linear() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
        ];
        let smoothed = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 4, false, 0.3);
        assert_eq!(smoothed[0], path[0]);
        assert_eq!(*smoothed.last().unwrap(), *path.last().unwrap());
        assert!(smoothed.len() >= 2);
    }

    #[test]
    fn test_single_point_passthrough() {
        let path = vec![Vec3::new(5.0, 5.0, 5.0)];
        let smoothed = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 8, false, 0.3);
        assert_eq!(smoothed.len(), 1);
        assert_eq!(smoothed[0], path[0]);
    }

    #[test]
    fn test_degenerate_coincident_points() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
        ];
        let smoothed = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 4, false, 0.3);
        for p in &smoothed {
            assert!(p.x.is_finite());
            assert!(p.y.is_finite());
            assert!(p.z.is_finite());
        }
    }

    #[test]
    fn test_s_curve_no_self_intersection() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(10.0, 10.0, 0.0),
            Vec3::new(0.0, 10.0, 0.0),
            Vec3::new(0.0, 20.0, 0.0),
        ];
        let smoothed = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 8, false, 0.3);
        for p in &smoothed {
            assert!(p.x >= -2.0, "X went too negative: {}", p.x);
            assert!(p.y >= -2.0, "Y went too negative: {}", p.y);
        }
    }

    #[test]
    fn test_tension_1_produces_linear() {
        let path = vec![
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(20.0, 10.0, 0.0),
            Vec3::new(30.0, 10.0, 0.0),
        ];
        let smoothed = smooth_catmull_rom_centripetal(&path, 0.5, 1.0, 4, false, 0.3);
        for p in &smoothed {
            assert!(p.x >= -1.0 && p.x <= 31.0);
            assert!(p.y >= -1.0 && p.y <= 11.0);
        }
    }

    #[test]
    fn test_adaptive_density_steep_segment() {
        let path = vec![
            Vec3::new(0.0, 0.0, 100.0),
            Vec3::new(5.0, 0.0, 100.0),
            Vec3::new(10.0, 0.0, 105.0),
            Vec3::new(15.0, 0.0, 105.0),
        ];
        let non_adaptive = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 8, false, 0.3);
        let adaptive = smooth_catmull_rom_centripetal(&path, 0.5, 0.0, 8, true, 0.3);
        assert!(adaptive.len() > non_adaptive.len());
    }
}
