use std::sync::Arc;

use segment::types::{Filter as SegmentFilter, PointIdType};
use shard::operations::point_ops::{
    PointIdsList, PointInsertOperationsInternal, VectorStructPersisted,
};
use shard::operations::{CollectionUpdateOperations, payload_ops, point_ops, vector_ops};

use crate::filter::Filter;
use crate::types::{Point, PointId, PointVectors, json_to_payload};

// ── UpdateMode ──────────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum UpdateMode {
    Upsert,
    InsertOnly,
    UpdateOnly,
}

impl From<UpdateMode> for shard::operations::point_ops::UpdateMode {
    fn from(m: UpdateMode) -> Self {
        match m {
            UpdateMode::Upsert => shard::operations::point_ops::UpdateMode::Upsert,
            UpdateMode::InsertOnly => shard::operations::point_ops::UpdateMode::InsertOnly,
            UpdateMode::UpdateOnly => shard::operations::point_ops::UpdateMode::UpdateOnly,
        }
    }
}

// ── UpdateOperation ─────────────────────────────────────────────────────────

/// Builds update operations. Each constructor returns an opaque operation
/// that can be passed to `EdgeShard.update()`.
#[derive(uniffi::Object)]
pub struct UpdateOperation {
    pub(crate) inner: CollectionUpdateOperations,
}

#[uniffi::export]
impl UpdateOperation {
    #[uniffi::constructor]
    pub fn upsert_points(
        points: Vec<Point>,
    ) -> std::result::Result<Arc<Self>, crate::error::EdgeError> {
        let internal_points: std::result::Result<Vec<_>, _> =
            points.into_iter().map(|p| p.into_internal()).collect();
        let internal_points =
            internal_points.map_err(|e| crate::error::EdgeError::OperationError { message: e })?;
        let points = PointInsertOperationsInternal::PointsList(internal_points);
        let operation = point_ops::PointOperations::UpsertPoints(points);
        Ok(Arc::new(Self {
            inner: CollectionUpdateOperations::PointOperation(operation),
        }))
    }

    #[uniffi::constructor]
    pub fn delete_points(point_ids: Vec<PointId>) -> Arc<Self> {
        let ids: Vec<PointIdType> = point_ids.into_iter().map(PointIdType::from).collect();
        let operation = point_ops::PointOperations::DeletePoints { ids };
        Arc::new(Self {
            inner: CollectionUpdateOperations::PointOperation(operation),
        })
    }

    #[uniffi::constructor]
    pub fn delete_points_by_filter(filter: Filter) -> Arc<Self> {
        let operation = point_ops::PointOperations::DeletePointsByFilter(SegmentFilter::from(filter));
        Arc::new(Self {
            inner: CollectionUpdateOperations::PointOperation(operation),
        })
    }

    #[uniffi::constructor]
    pub fn update_vectors(point_vectors: Vec<PointVectors>) -> Arc<Self> {
        let points = point_vectors
            .into_iter()
            .map(|pv| shard::operations::vector_ops::PointVectorsPersisted {
                id: PointIdType::from(pv.id),
                vector: VectorStructPersisted::from(pv.vector),
            })
            .collect();
        let operation =
            vector_ops::VectorOperations::UpdateVectors(vector_ops::UpdateVectorsOp {
                points,
                update_filter: None,
            });
        Arc::new(Self {
            inner: CollectionUpdateOperations::VectorOperation(operation),
        })
    }

    #[uniffi::constructor]
    pub fn delete_vectors(point_ids: Vec<PointId>, vector_names: Vec<String>) -> Arc<Self> {
        let ids: Vec<PointIdType> = point_ids.into_iter().map(PointIdType::from).collect();
        let operation =
            vector_ops::VectorOperations::DeleteVectors(PointIdsList::from(ids), vector_names);
        Arc::new(Self {
            inner: CollectionUpdateOperations::VectorOperation(operation),
        })
    }

    #[uniffi::constructor]
    pub fn set_payload(
        point_ids: Vec<PointId>,
        payload_json: String,
    ) -> std::result::Result<Arc<Self>, crate::error::EdgeError> {
        let payload = json_to_payload(&payload_json)
            .map_err(|e| crate::error::EdgeError::OperationError { message: e })?;
        let ids: Vec<PointIdType> = point_ids.into_iter().map(PointIdType::from).collect();
        let operation = payload_ops::PayloadOps::SetPayload(payload_ops::SetPayloadOp {
            payload,
            points: Some(ids),
            filter: None,
            key: None,
        });
        Ok(Arc::new(Self {
            inner: CollectionUpdateOperations::PayloadOperation(operation),
        }))
    }

    #[uniffi::constructor]
    pub fn delete_payload(point_ids: Vec<PointId>, keys: Vec<String>) -> Arc<Self> {
        let ids: Vec<PointIdType> = point_ids.into_iter().map(PointIdType::from).collect();
        let keys = keys
            .into_iter()
            .map(|k| k.parse().expect("valid json path"))
            .collect();
        let operation = payload_ops::PayloadOps::DeletePayload(payload_ops::DeletePayloadOp {
            keys,
            points: Some(ids),
            filter: None,
        });
        Arc::new(Self {
            inner: CollectionUpdateOperations::PayloadOperation(operation),
        })
    }

    #[uniffi::constructor]
    pub fn clear_payload(point_ids: Vec<PointId>) -> Arc<Self> {
        let ids: Vec<PointIdType> = point_ids.into_iter().map(PointIdType::from).collect();
        let operation = payload_ops::PayloadOps::ClearPayload { points: ids };
        Arc::new(Self {
            inner: CollectionUpdateOperations::PayloadOperation(operation),
        })
    }
}
