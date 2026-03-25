use std::collections::HashMap;

use segment::data_types::vectors::VectorStructInternal;
use segment::types::{
    Payload, PointIdType, ScoredPoint as SegmentScoredPoint,
    WithPayloadInterface, WithVector as SegmentWithVector,
};
use shard::operations::point_ops::{
    PointStructPersisted, VectorPersisted, VectorStructPersisted,
};
use shard::retrieve::record_internal::RecordInternal;
use sparse::common::sparse_vector::SparseVector;

// ── PointId ─────────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Enum)]
pub enum PointId {
    NumId { value: u64 },
    Uuid { value: String },
}

impl From<PointId> for PointIdType {
    fn from(id: PointId) -> Self {
        match id {
            PointId::NumId { value } => PointIdType::NumId(value),
            PointId::Uuid { value } => {
                PointIdType::Uuid(uuid::Uuid::parse_str(&value).expect("valid UUID"))
            }
        }
    }
}

impl From<PointIdType> for PointId {
    fn from(id: PointIdType) -> Self {
        match id {
            PointIdType::NumId(value) => PointId::NumId { value },
            PointIdType::Uuid(value) => PointId::Uuid {
                value: value.to_string(),
            },
        }
    }
}

// ── SparseVector ────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct EdgeSparseVector {
    pub indices: Vec<u32>,
    pub values: Vec<f32>,
}

impl From<EdgeSparseVector> for SparseVector {
    fn from(v: EdgeSparseVector) -> Self {
        SparseVector {
            indices: v.indices,
            values: v.values,
        }
    }
}

impl From<SparseVector> for EdgeSparseVector {
    fn from(v: SparseVector) -> Self {
        EdgeSparseVector {
            indices: v.indices,
            values: v.values,
        }
    }
}

// ── NamedVector ─────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Enum)]
pub enum NamedVector {
    Dense { values: Vec<f32> },
    Sparse { vector: EdgeSparseVector },
    MultiDense { vectors: Vec<Vec<f32>> },
}

impl From<NamedVector> for VectorPersisted {
    fn from(v: NamedVector) -> Self {
        match v {
            NamedVector::Dense { values } => VectorPersisted::Dense(values),
            NamedVector::Sparse { vector } => {
                VectorPersisted::Sparse(SparseVector::from(vector))
            }
            NamedVector::MultiDense { vectors } => VectorPersisted::MultiDense(vectors),
        }
    }
}

impl From<VectorPersisted> for NamedVector {
    fn from(v: VectorPersisted) -> Self {
        match v {
            VectorPersisted::Dense(values) => NamedVector::Dense { values },
            VectorPersisted::Sparse(vector) => NamedVector::Sparse {
                vector: EdgeSparseVector::from(vector),
            },
            VectorPersisted::MultiDense(vectors) => NamedVector::MultiDense { vectors },
        }
    }
}

// ── Vector (top-level input for point construction) ─────────────────────────

#[derive(Clone, Debug, uniffi::Enum)]
pub enum Vector {
    Single { values: Vec<f32> },
    MultiDense { vectors: Vec<Vec<f32>> },
    Named { map: HashMap<String, NamedVector> },
}

impl From<Vector> for VectorStructPersisted {
    fn from(v: Vector) -> Self {
        match v {
            Vector::Single { values } => VectorStructPersisted::Single(values),
            Vector::MultiDense { vectors } => VectorStructPersisted::MultiDense(vectors),
            Vector::Named { map } => VectorStructPersisted::Named(
                map.into_iter()
                    .map(|(k, v)| (k, VectorPersisted::from(v)))
                    .collect(),
            ),
        }
    }
}

impl From<VectorStructPersisted> for Vector {
    fn from(v: VectorStructPersisted) -> Self {
        match v {
            VectorStructPersisted::Single(values) => Vector::Single { values },
            VectorStructPersisted::MultiDense(vectors) => Vector::MultiDense { vectors },
            VectorStructPersisted::Named(map) => Vector::Named {
                map: map
                    .into_iter()
                    .map(|(k, v)| (k, NamedVector::from(v)))
                    .collect(),
            },
        }
    }
}

// ── Payload (JSON string) ───────────────────────────────────────────────────

/// Payload is represented as a JSON string across the FFI boundary.
pub fn payload_to_json(payload: &Payload) -> String {
    serde_json::to_string(&payload.0).unwrap_or_default()
}

pub fn json_to_payload(json: &str) -> std::result::Result<Payload, String> {
    let map: serde_json::Map<String, serde_json::Value> =
        serde_json::from_str(json).map_err(|e| e.to_string())?;
    Ok(Payload(map))
}

fn vector_struct_internal_to_json(v: &VectorStructInternal) -> String {
    match v {
        VectorStructInternal::Single(dense) => serde_json::to_string(dense).unwrap_or_default(),
        VectorStructInternal::MultiDense(multi) => {
            serde_json::to_string(multi).unwrap_or_default()
        }
        VectorStructInternal::Named(map) => serde_json::to_string(map).unwrap_or_default(),
    }
}

// ── WithPayload / WithVector ────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Enum)]
pub enum WithPayload {
    Bool { enable: bool },
    Fields { fields: Vec<String> },
}

impl From<WithPayload> for WithPayloadInterface {
    fn from(w: WithPayload) -> Self {
        match w {
            WithPayload::Bool { enable } => WithPayloadInterface::Bool(enable),
            WithPayload::Fields { fields } => {
                WithPayloadInterface::Fields(fields.into_iter().filter_map(|f| f.parse().ok()).collect())
            }
        }
    }
}

#[derive(Clone, Debug, uniffi::Enum)]
pub enum WithVector {
    Bool { enable: bool },
    Names { names: Vec<String> },
}

impl From<WithVector> for SegmentWithVector {
    fn from(w: WithVector) -> Self {
        match w {
            WithVector::Bool { enable } => SegmentWithVector::Bool(enable),
            WithVector::Names { names } => SegmentWithVector::Selector(names),
        }
    }
}

// ── Point ───────────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct Point {
    pub id: PointId,
    pub vector: Vector,
    pub payload: Option<String>,
}

impl Point {
    pub fn into_internal(self) -> std::result::Result<PointStructPersisted, String> {
        let payload = match self.payload {
            Some(json) => Some(json_to_payload(&json)?),
            None => None,
        };
        Ok(PointStructPersisted {
            id: PointIdType::from(self.id),
            vector: VectorStructPersisted::from(self.vector),
            payload,
        })
    }
}

// ── ScoredPoint ─────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct ScoredPoint {
    pub id: PointId,
    pub version: u64,
    pub score: f32,
    pub payload: Option<String>,
    pub vector: Option<String>,
}

impl From<SegmentScoredPoint> for ScoredPoint {
    fn from(p: SegmentScoredPoint) -> Self {
        ScoredPoint {
            id: PointId::from(p.id),
            version: p.version,
            score: p.score,
            payload: p.payload.map(|p| payload_to_json(&p)),
            vector: p
                .vector
                .as_ref()
                .map(|v| vector_struct_internal_to_json(v)),
        }
    }
}

// ── Record ──────────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct Record {
    pub id: PointId,
    pub payload: Option<String>,
    pub vector: Option<String>,
}

impl From<RecordInternal> for Record {
    fn from(r: RecordInternal) -> Self {
        Record {
            id: PointId::from(r.id),
            payload: r.payload.map(|p| payload_to_json(&p)),
            vector: r
                .vector
                .as_ref()
                .map(|v| vector_struct_internal_to_json(v)),
        }
    }
}

// ── PointVectors (for update_vectors) ───────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct PointVectors {
    pub id: PointId,
    pub vector: Vector,
}
