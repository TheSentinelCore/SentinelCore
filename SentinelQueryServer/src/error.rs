use axum::http::{HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Serialize;
use serde_json::{json, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    InvalidParams,
    CtxUnresolved,
    CtxPartial,
    MapNotFound,
    EntityNotFound,
    FactionFilterUnsupported,
    DatasetNotReady,
    DatasetInvalid,
    PaginationInvalid,
    InternalError,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::InvalidParams => "INVALID_PARAMS",
            Self::CtxUnresolved => "CTX_UNRESOLVED",
            Self::CtxPartial => "CTX_PARTIAL",
            Self::MapNotFound => "MAP_NOT_FOUND",
            Self::EntityNotFound => "ENTITY_NOT_FOUND",
            Self::FactionFilterUnsupported => "FACTION_FILTER_UNSUPPORTED",
            Self::DatasetNotReady => "DATASET_NOT_READY",
            Self::DatasetInvalid => "DATASET_INVALID",
            Self::PaginationInvalid => "PAGINATION_INVALID",
            Self::InternalError => "INTERNAL_ERROR",
        }
    }

    pub fn status(self) -> StatusCode {
        match self {
            Self::InvalidParams | Self::PaginationInvalid | Self::FactionFilterUnsupported => {
                StatusCode::BAD_REQUEST
            }
            Self::CtxUnresolved | Self::CtxPartial => StatusCode::UNPROCESSABLE_ENTITY,
            Self::MapNotFound | Self::EntityNotFound => StatusCode::NOT_FOUND,
            Self::DatasetNotReady => StatusCode::SERVICE_UNAVAILABLE,
            Self::DatasetInvalid | Self::InternalError => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AppError {
    pub code: ErrorCode,
    pub message: String,
    pub details: Option<Value>,
    pub request_id: Option<String>,
}

#[derive(Debug, Serialize)]
struct ErrorBody {
    error: ErrorPayload,
    request_id: String,
}

#[derive(Debug, Serialize)]
struct ErrorPayload {
    code: String,
    message: String,
    details: Value,
}

impl AppError {
    pub fn new(code: ErrorCode, message: impl Into<String>, details: Option<Value>) -> Self {
        Self {
            code,
            message: message.into(),
            details,
            request_id: None,
        }
    }

    pub fn invalid_params(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InvalidParams, message, None)
    }

    pub fn pagination_invalid(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::PaginationInvalid, message, None)
    }

    pub fn map_not_found(map_id: i64) -> Self {
        Self::new(
            ErrorCode::MapNotFound,
            format!("map_id {} not found", map_id),
            Some(json!({ "map_id": map_id })),
        )
    }

    pub fn entity_not_found(entity: &str, id: i64) -> Self {
        Self::new(
            ErrorCode::EntityNotFound,
            format!("{} {} not found", entity, id),
            Some(json!({ "entity": entity, "id": id })),
        )
    }

    pub fn dataset_not_ready(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::DatasetNotReady, message, None)
    }

    pub fn dataset_invalid(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::DatasetInvalid, message, None)
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InternalError, message, None)
    }

    pub fn with_request_id(mut self, request_id: impl Into<String>) -> Self {
        self.request_id = Some(request_id.into());
        self
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let request_id = self
            .request_id
            .unwrap_or_else(|| "unknown-request-id".to_string());

        let body = ErrorBody {
            error: ErrorPayload {
                code: self.code.as_str().to_string(),
                message: self.message,
                details: self.details.unwrap_or(Value::Null),
            },
            request_id: request_id.clone(),
        };

        let mut response = (self.code.status(), Json(body)).into_response();
        response
            .headers_mut()
            .insert("x-error-code", HeaderValue::from_static(self.code.as_str()));

        if let Ok(value) = HeaderValue::from_str(&request_id) {
            response.headers_mut().insert("x-request-id", value);
        }

        response
    }
}

impl From<anyhow::Error> for AppError {
    fn from(value: anyhow::Error) -> Self {
        Self::internal(value.to_string())
    }
}

impl From<rusqlite::Error> for AppError {
    fn from(value: rusqlite::Error) -> Self {
        Self::internal(value.to_string())
    }
}

pub type AppResult<T> = Result<T, AppError>;
