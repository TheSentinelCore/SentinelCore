//! Core geometry types for Detour navigation.

/// A 3D vector representing world positions and directions.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
#[repr(C)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vec3 {
    pub const ZERO: Vec3 = Vec3 { x: 0.0, y: 0.0, z: 0.0 };

    /// Create a new Vec3.
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    /// Create from a float array.
    pub fn from_array(arr: [f32; 3]) -> Self {
        Self { x: arr[0], y: arr[1], z: arr[2] }
    }

    /// Convert to float array.
    pub fn to_array(&self) -> [f32; 3] {
        [self.x, self.y, self.z]
    }

    /// Get pointer to first element (for FFI).
    pub fn as_ptr(&self) -> *const f32 {
        &self.x as *const f32
    }

    /// Get mutable pointer to first element (for FFI).
    pub fn as_mut_ptr(&mut self) -> *mut f32 {
        &mut self.x as *mut f32
    }

    /// Convert WoW coordinates to Detour coordinates.
    ///
    /// WoW uses: X=North-South, Y=West-East, Z=Height
    /// Detour uses: X=West-East, Y=Height, Z=North-South
    ///
    /// So: Detour(X, Y, Z) = (WoW.Y, WoW.Z, WoW.X)
    pub fn to_detour(&self) -> [f32; 3] {
        [self.y, self.z, self.x]
    }

    /// Convert Detour coordinates to WoW coordinates.
    ///
    /// Detour[0]=WoW.Y, Detour[1]=WoW.Z, Detour[2]=WoW.X
    pub fn from_detour(d: [f32; 3]) -> Self {
        Self { x: d[2], y: d[0], z: d[1] }
    }

    /// Calculate 3D distance to another point.
    pub fn distance(&self, other: &Vec3) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        let dz = self.z - other.z;
        (dx * dx + dy * dy + dz * dz).sqrt()
    }

    /// Calculate 2D distance (ignoring height) to another point.
    pub fn distance_2d(&self, other: &Vec3) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        (dx * dx + dy * dy).sqrt()
    }

    /// Calculate the length of this vector.
    pub fn length(&self) -> f32 {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }

    /// Return a normalized version of this vector.
    pub fn normalize(&self) -> Vec3 {
        let len = self.length();
        if len > 0.0 {
            Vec3::new(self.x / len, self.y / len, self.z / len)
        } else {
            Vec3::ZERO
        }
    }
}

impl std::ops::Add for Vec3 {
    type Output = Vec3;
    fn add(self, rhs: Vec3) -> Vec3 {
        Vec3::new(self.x + rhs.x, self.y + rhs.y, self.z + rhs.z)
    }
}

impl std::ops::Sub for Vec3 {
    type Output = Vec3;
    fn sub(self, rhs: Vec3) -> Vec3 {
        Vec3::new(self.x - rhs.x, self.y - rhs.y, self.z - rhs.z)
    }
}

impl std::ops::Mul<f32> for Vec3 {
    type Output = Vec3;
    fn mul(self, rhs: f32) -> Vec3 {
        Vec3::new(self.x * rhs, self.y * rhs, self.z * rhs)
    }
}

/// Polygon reference - unique identifier for a polygon in the navmesh.
pub type PolyRef = u64;

/// Tile reference - unique identifier for a tile.
pub type TileRef = u64;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vec3_basic() {
        let v = Vec3::new(1.0, 2.0, 3.0);
        assert_eq!(v.x, 1.0);
        assert_eq!(v.y, 2.0);
        assert_eq!(v.z, 3.0);
    }

    #[test]
    fn test_vec3_to_detour() {
        // WoW position: X=100 (north), Y=200 (west), Z=50 (height)
        let wow_pos = Vec3::new(100.0, 200.0, 50.0);
        let detour = wow_pos.to_detour();

        // Detour should be: [WoW.Y, WoW.Z, WoW.X] = [200, 50, 100]
        assert_eq!(detour, [200.0, 50.0, 100.0]);
    }

    #[test]
    fn test_vec3_from_detour() {
        // Detour result: [200, 50, 100]
        let detour = [200.0, 50.0, 100.0];
        let wow_pos = Vec3::from_detour(detour);

        // WoW should be: X=detour[2], Y=detour[0], Z=detour[1]
        assert_eq!(wow_pos.x, 100.0);
        assert_eq!(wow_pos.y, 200.0);
        assert_eq!(wow_pos.z, 50.0);
    }

    #[test]
    fn test_vec3_roundtrip() {
        let original = Vec3::new(123.45, 678.90, 111.22);
        let detour = original.to_detour();
        let back = Vec3::from_detour(detour);

        assert!((original.x - back.x).abs() < 0.001);
        assert!((original.y - back.y).abs() < 0.001);
        assert!((original.z - back.z).abs() < 0.001);
    }

    #[test]
    fn test_vec3_distance() {
        let a = Vec3::new(0.0, 0.0, 0.0);
        let b = Vec3::new(3.0, 4.0, 0.0);
        assert_eq!(a.distance(&b), 5.0);
    }
}
