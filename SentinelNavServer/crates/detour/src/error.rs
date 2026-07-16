//! Error types for Detour operations.

use thiserror::Error;

/// Errors that can occur during Detour operations.
#[derive(Debug, Error)]
pub enum DetourError {
    #[error("Memory allocation failed")]
    AllocationFailed,

    #[error("NavMesh initialization failed: status 0x{0:08X}")]
    InitFailed(u32),

    #[error("Start position not on navmesh")]
    StartNotFound,

    #[error("End position not on navmesh")]
    EndNotFound,

    #[error("No path found between positions")]
    PathNotFound,

    #[error("Straight path calculation failed")]
    StraightPathFailed,

    #[error("Tile add failed: status 0x{0:08X}")]
    TileAddFailed(u32),

    #[error("Query initialization failed")]
    QueryInitFailed,

    #[error("Detour operation failed: status 0x{0:08X}")]
    StatusError(u32),
}

/// Detour status code wrapper.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DetourStatus(pub u32);

impl DetourStatus {
    // Status flags from DetourStatus.h
    pub const DT_FAILURE: u32 = 1 << 31;
    pub const DT_SUCCESS: u32 = 1 << 30;
    pub const DT_IN_PROGRESS: u32 = 1 << 29;

    // Detail flags
    pub const DT_WRONG_MAGIC: u32 = 1 << 0;
    pub const DT_WRONG_VERSION: u32 = 1 << 1;
    pub const DT_OUT_OF_MEMORY: u32 = 1 << 2;
    pub const DT_INVALID_PARAM: u32 = 1 << 3;
    pub const DT_BUFFER_TOO_SMALL: u32 = 1 << 4;
    pub const DT_OUT_OF_NODES: u32 = 1 << 5;
    pub const DT_PARTIAL_RESULT: u32 = 1 << 6;
    pub const DT_ALREADY_OCCUPIED: u32 = 1 << 7;

    /// Check if the status indicates success.
    pub fn succeeded(&self) -> bool {
        (self.0 & Self::DT_SUCCESS) != 0
    }

    /// Check if the status indicates failure.
    pub fn failed(&self) -> bool {
        (self.0 & Self::DT_FAILURE) != 0
    }

    /// Check if the operation is still in progress.
    pub fn in_progress(&self) -> bool {
        (self.0 & Self::DT_IN_PROGRESS) != 0
    }

    /// Check if this is a partial result.
    pub fn is_partial(&self) -> bool {
        (self.0 & Self::DT_PARTIAL_RESULT) != 0
    }

    /// Convert to Result.
    pub fn to_result(self) -> Result<(), DetourError> {
        if self.succeeded() {
            Ok(())
        } else {
            Err(DetourError::StatusError(self.0))
        }
    }
}

/// Helper function to check if a dtStatus indicates success.
pub fn dt_status_succeeded(status: u32) -> bool {
    (status & DetourStatus::DT_SUCCESS) != 0
}

/// Helper function to check if a dtStatus indicates failure.
pub fn dt_status_failed(status: u32) -> bool {
    (status & DetourStatus::DT_FAILURE) != 0
}

#[cfg(test)]
mod tests {
    use super::*;

    // TICKET-008: DetourStatus tests
    #[test]
    fn test_detour_status_success() {
        let status = DetourStatus(DetourStatus::DT_SUCCESS);
        assert!(status.succeeded());
        assert!(!status.failed());
        assert!(!status.in_progress());
    }

    #[test]
    fn test_detour_status_failure() {
        let status = DetourStatus(DetourStatus::DT_FAILURE);
        assert!(!status.succeeded());
        assert!(status.failed());
    }

    #[test]
    fn test_detour_status_partial() {
        let status = DetourStatus(DetourStatus::DT_SUCCESS | DetourStatus::DT_PARTIAL_RESULT);
        assert!(status.succeeded());
        assert!(status.is_partial());
    }

    #[test]
    fn test_detour_status_to_result_success() {
        let status = DetourStatus(DetourStatus::DT_SUCCESS);
        assert!(status.to_result().is_ok());
    }

    #[test]
    fn test_detour_status_to_result_failure() {
        let status = DetourStatus(DetourStatus::DT_FAILURE | DetourStatus::DT_INVALID_PARAM);
        let result = status.to_result();
        assert!(result.is_err());
        match result {
            Err(DetourError::StatusError(code)) => {
                assert_eq!(code, DetourStatus::DT_FAILURE | DetourStatus::DT_INVALID_PARAM);
            }
            _ => panic!("Expected StatusError"),
        }
    }

    #[test]
    fn test_helper_functions() {
        let success = DetourStatus::DT_SUCCESS;
        let failure = DetourStatus::DT_FAILURE;

        assert!(dt_status_succeeded(success));
        assert!(!dt_status_succeeded(failure));
        assert!(dt_status_failed(failure));
        assert!(!dt_status_failed(success));
    }

    // TICKET-009: DetourError tests
    #[test]
    fn test_error_display_messages() {
        let err = DetourError::AllocationFailed;
        assert_eq!(format!("{}", err), "Memory allocation failed");

        let err = DetourError::InitFailed(0x80000008);
        assert!(format!("{}", err).contains("80000008"));

        let err = DetourError::StartNotFound;
        assert_eq!(format!("{}", err), "Start position not on navmesh");

        let err = DetourError::PathNotFound;
        assert_eq!(format!("{}", err), "No path found between positions");
    }

    #[test]
    fn test_error_is_std_error() {
        fn assert_error<E: std::error::Error>() {}
        assert_error::<DetourError>();
    }
}
