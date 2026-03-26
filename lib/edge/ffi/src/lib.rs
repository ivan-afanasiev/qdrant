pub mod config;
pub mod error;
pub mod filter;
pub mod query;
pub mod types;
pub mod update;

use std::path::PathBuf;
use std::sync::Arc;

use parking_lot::Mutex;
use segment::data_types::facets::FacetValue;
use segment::types::{PointIdType, SegmentConfig, WithPayloadInterface, WithVector as SegmentWithVector};

use crate::config::EdgeConfig;
use crate::error::{EdgeError, Result};
use crate::query::*;
use crate::types::*;
use crate::update::UpdateOperation;

uniffi::setup_scaffolding!();

#[derive(uniffi::Object)]
pub struct EdgeShard {
    inner: Mutex<Option<edge::EdgeShard>>,
}

#[uniffi::export]
impl EdgeShard {
    #[uniffi::constructor]
    pub fn load(path: String, config: Option<EdgeConfig>) -> Result<Arc<Self>> {
        let segment_config = config.map(SegmentConfig::from);
        let shard = edge::EdgeShard::load(&PathBuf::from(path), segment_config)?;
        Ok(Arc::new(Self {
            inner: Mutex::new(Some(shard)),
        }))
    }

    pub fn flush(&self) -> Result<()> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        shard.flush();
        Ok(())
    }

    pub fn close(&self) {
        self.inner.lock().take();
    }

    pub fn update(&self, operation: Arc<UpdateOperation>) -> Result<()> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        shard.update(operation.inner.clone())?;
        Ok(())
    }

    pub fn query(&self, request: QueryRequest) -> Result<Vec<ScoredPoint>> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        let points = shard.query(request.into())?;
        Ok(points.into_iter().map(ScoredPoint::from).collect())
    }

    pub fn search(&self, request: SearchRequest) -> Result<Vec<ScoredPoint>> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        let points = shard.search(request.into())?;
        Ok(points.into_iter().map(ScoredPoint::from).collect())
    }

    pub fn scroll(
        &self,
        request: ScrollRequest,
    ) -> Result<ScrollResponse> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        let (records, next_offset) = shard.scroll(request.into())?;
        Ok(ScrollResponse {
            records: records.into_iter().map(Record::from).collect(),
            next_offset: next_offset.map(PointId::from),
        })
    }

    pub fn count(&self, request: CountRequest) -> Result<u64> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        let count = shard.count(request.into())?;
        Ok(count as u64)
    }

    pub fn facet(&self, request: FacetRequest) -> Result<FacetResponse> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        let response = shard.facet(request.into())?;
        let hits = response
            .hits
            .into_iter()
            .map(|h| FacetHit {
                value: match &h.value {
                    FacetValue::Keyword(s) => s.clone(),
                    FacetValue::Int(i) => i.to_string(),
                    FacetValue::Uuid(u) => uuid::Uuid::from_u128(*u).to_string(),
                    FacetValue::Bool(b) => b.to_string(),
                },
                count: h.count as u64,
            })
            .collect();
        Ok(FacetResponse { hits })
    }

    pub fn retrieve(
        &self,
        point_ids: Vec<PointId>,
        with_payload: Option<WithPayload>,
        with_vector: Option<WithVector>,
    ) -> Result<Vec<Record>> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        let ids: Vec<PointIdType> = point_ids.into_iter().map(PointIdType::from).collect();
        let records = shard.retrieve(
            &ids,
            with_payload.map(WithPayloadInterface::from),
            with_vector.map(SegmentWithVector::from),
        )?;
        Ok(records.into_iter().map(Record::from).collect())
    }

    pub fn info(&self) -> Result<ShardInfo> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        let info = shard.info();
        Ok(ShardInfo {
            segments_count: info.segments_count as u64,
            points_count: info.points_count as u64,
            indexed_vectors_count: info.indexed_vectors_count as u64,
        })
    }

    pub fn config(&self) -> Result<EdgeConfig> {
        let guard = self.inner.lock();
        let shard = guard.as_ref().ok_or(EdgeError::OperationError {
            message: "EdgeShard is closed".into(),
        })?;
        Ok(EdgeConfig::from(shard.config().clone()))
    }
}

#[uniffi::export]
pub fn unpack_snapshot(snapshot_path: String, target_path: String) -> Result<()> {
    edge::EdgeShard::unpack_snapshot(
        &PathBuf::from(snapshot_path),
        &PathBuf::from(target_path),
    )?;
    Ok(())
}

// ── ScrollResponse ──────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct ScrollResponse {
    pub records: Vec<Record>,
    pub next_offset: Option<PointId>,
}
