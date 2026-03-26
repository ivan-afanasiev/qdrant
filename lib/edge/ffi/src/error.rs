use segment::common::operation_error::OperationError;

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum EdgeError {
    #[error("{message}")]
    OperationError { message: String },
}

impl From<OperationError> for EdgeError {
    fn from(err: OperationError) -> Self {
        EdgeError::OperationError {
            message: err.to_string(),
        }
    }
}

pub type Result<T, E = EdgeError> = std::result::Result<T, E>;
