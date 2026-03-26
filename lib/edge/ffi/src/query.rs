use ordered_float::OrderedFloat;
use segment::data_types::order_by::{Direction as SegmentDirection, OrderBy as SegmentOrderBy};
use segment::data_types::vectors::{DEFAULT_VECTOR_NAME, VectorInternal};
use segment::types::{
    Filter as SegmentFilter, PointIdType,
    SearchParams as SegmentSearchParams, WithPayloadInterface,
    WithVector as SegmentWithVector,
};
use shard::count::CountRequestInternal;
use shard::facet::FacetRequestInternal;
use shard::query::*;
use shard::query::query_enum::QueryEnum;
use shard::scroll::{OrderByInterface, ScrollRequestInternal};
use shard::search::CoreSearchRequest;

use crate::filter::Filter;
use crate::types::{PointId, WithPayload, WithVector};

// ── SearchParams ────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchParams {
    pub hnsw_ef: Option<u64>,
    pub exact: bool,
    pub indexed_only: bool,
}

impl From<SearchParams> for SegmentSearchParams {
    fn from(p: SearchParams) -> Self {
        SegmentSearchParams {
            hnsw_ef: p.hnsw_ef.map(|v| v as usize),
            exact: p.exact,
            quantization: None,
            indexed_only: p.indexed_only,
            acorn: None,
        }
    }
}

// ── Query (nearest vector query) ────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Enum)]
pub enum Query {
    Nearest {
        vector: Vec<f32>,
        using: Option<String>,
    },
}

impl From<Query> for QueryEnum {
    fn from(q: Query) -> Self {
        match q {
            Query::Nearest { vector, using } => {
                let using = using.unwrap_or_else(|| DEFAULT_VECTOR_NAME.to_string());
                QueryEnum::Nearest(segment::data_types::vectors::NamedQuery {
                    query: VectorInternal::Dense(vector),
                    using: Some(using),
                })
            }
        }
    }
}

// ── ScoringQuery ────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Enum)]
pub enum ScoringQuery {
    Vector { query: Query },
    Fusion { fusion: Fusion },
    OrderBy { order_by: OrderBy },
    Sample { sample: Sample },
}

impl From<ScoringQuery> for shard::query::ScoringQuery {
    fn from(q: ScoringQuery) -> Self {
        match q {
            ScoringQuery::Vector { query } => {
                shard::query::ScoringQuery::Vector(QueryEnum::from(query))
            }
            ScoringQuery::Fusion { fusion } => {
                shard::query::ScoringQuery::Fusion(FusionInternal::from(fusion))
            }
            ScoringQuery::OrderBy { order_by } => {
                shard::query::ScoringQuery::OrderBy(SegmentOrderBy::from(order_by))
            }
            ScoringQuery::Sample { sample } => {
                shard::query::ScoringQuery::Sample(SampleInternal::from(sample))
            }
        }
    }
}

// ── Fusion ──────────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Enum)]
pub enum Fusion {
    Rrf { k: u64 },
    Dbsf,
}

impl From<Fusion> for FusionInternal {
    fn from(f: Fusion) -> Self {
        match f {
            Fusion::Rrf { k } => FusionInternal::Rrf {
                k: k as usize,
                weights: None,
            },
            Fusion::Dbsf => FusionInternal::Dbsf,
        }
    }
}

// ── OrderBy ─────────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct OrderBy {
    pub key: String,
    pub direction: Option<Direction>,
}

impl From<OrderBy> for SegmentOrderBy {
    fn from(o: OrderBy) -> Self {
        SegmentOrderBy {
            key: o.key.parse().expect("valid json path"),
            direction: o.direction.map(SegmentDirection::from),
            start_from: None,
        }
    }
}

// ── Direction ───────────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum Direction {
    Asc,
    Desc,
}

impl From<Direction> for SegmentDirection {
    fn from(d: Direction) -> Self {
        match d {
            Direction::Asc => SegmentDirection::Asc,
            Direction::Desc => SegmentDirection::Desc,
        }
    }
}

// ── Sample ──────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum Sample {
    Random,
}

impl From<Sample> for SampleInternal {
    fn from(s: Sample) -> Self {
        match s {
            Sample::Random => SampleInternal::Random,
        }
    }
}

// ── Prefetch ────────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct Prefetch {
    pub limit: u64,
    pub query: Option<ScoringQuery>,
    pub prefetches: Vec<Prefetch>,
    pub filter: Option<Filter>,
    pub score_threshold: Option<f32>,
    pub params: Option<SearchParams>,
}

impl From<Prefetch> for ShardPrefetch {
    fn from(p: Prefetch) -> Self {
        ShardPrefetch {
            prefetches: p.prefetches.into_iter().map(ShardPrefetch::from).collect(),
            limit: p.limit as usize,
            query: p.query.map(shard::query::ScoringQuery::from),
            params: p.params.map(SegmentSearchParams::from),
            filter: p.filter.map(SegmentFilter::from),
            score_threshold: p.score_threshold.map(OrderedFloat),
        }
    }
}

// ── QueryRequest ────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct QueryRequest {
    pub limit: u64,
    pub offset: Option<u64>,
    pub query: Option<ScoringQuery>,
    pub prefetches: Vec<Prefetch>,
    pub with_vector: Option<WithVector>,
    pub with_payload: Option<WithPayload>,
    pub filter: Option<Filter>,
    pub score_threshold: Option<f32>,
    pub params: Option<SearchParams>,
}

impl From<QueryRequest> for ShardQueryRequest {
    fn from(r: QueryRequest) -> Self {
        ShardQueryRequest {
            prefetches: r.prefetches.into_iter().map(ShardPrefetch::from).collect(),
            limit: r.limit as usize,
            offset: r.offset.unwrap_or(0) as usize,
            with_vector: r.with_vector.map(SegmentWithVector::from).unwrap_or_default(),
            with_payload: r
                .with_payload
                .map(WithPayloadInterface::from)
                .unwrap_or_default(),
            query: r.query.map(shard::query::ScoringQuery::from),
            filter: r.filter.map(SegmentFilter::from),
            score_threshold: r.score_threshold.map(OrderedFloat),
            params: r.params.map(SegmentSearchParams::from),
        }
    }
}

// ── SearchRequest ───────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct SearchRequest {
    pub query: Query,
    pub limit: u64,
    pub offset: Option<u64>,
    pub filter: Option<Filter>,
    pub params: Option<SearchParams>,
    pub with_vector: Option<WithVector>,
    pub with_payload: Option<WithPayload>,
    pub score_threshold: Option<f32>,
}

impl From<SearchRequest> for CoreSearchRequest {
    fn from(r: SearchRequest) -> Self {
        CoreSearchRequest {
            query: QueryEnum::from(r.query),
            limit: r.limit as usize,
            offset: r.offset.unwrap_or(0) as usize,
            filter: r.filter.map(SegmentFilter::from),
            params: r.params.map(SegmentSearchParams::from),
            with_vector: r.with_vector.map(SegmentWithVector::from),
            with_payload: r.with_payload.map(WithPayloadInterface::from),
            score_threshold: r.score_threshold,
        }
    }
}

// ── ScrollRequest ───────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct ScrollRequest {
    pub offset: Option<PointId>,
    pub limit: Option<u64>,
    pub filter: Option<Filter>,
    pub with_payload: Option<WithPayload>,
    pub with_vector: Option<WithVector>,
    pub order_by: Option<OrderBy>,
}

impl From<ScrollRequest> for ScrollRequestInternal {
    fn from(r: ScrollRequest) -> Self {
        ScrollRequestInternal {
            offset: r.offset.map(PointIdType::from),
            limit: r.limit.map(|v| v as usize),
            filter: r.filter.map(SegmentFilter::from),
            with_payload: r.with_payload.map(WithPayloadInterface::from),
            with_vector: r.with_vector.map(SegmentWithVector::from).unwrap_or_default(),
            order_by: r.order_by.map(|o| OrderByInterface::Struct(SegmentOrderBy::from(o))),
        }
    }
}

// ── CountRequest ────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct CountRequest {
    pub filter: Option<Filter>,
    pub exact: bool,
}

impl From<CountRequest> for CountRequestInternal {
    fn from(r: CountRequest) -> Self {
        CountRequestInternal {
            filter: r.filter.map(SegmentFilter::from),
            exact: r.exact,
        }
    }
}

// ── FacetRequest ────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct FacetRequest {
    pub key: String,
    pub limit: u64,
    pub exact: bool,
    pub filter: Option<Filter>,
}

impl From<FacetRequest> for FacetRequestInternal {
    fn from(r: FacetRequest) -> Self {
        FacetRequestInternal {
            key: r.key.parse().expect("valid json path"),
            limit: r.limit as usize,
            filter: r.filter.map(SegmentFilter::from),
            exact: r.exact,
        }
    }
}

// ── FacetResponse ───────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct FacetHit {
    pub value: String,
    pub count: u64,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct FacetResponse {
    pub hits: Vec<FacetHit>,
}

// ── ShardInfo ───────────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct ShardInfo {
    pub segments_count: u64,
    pub points_count: u64,
    pub indexed_vectors_count: u64,
}
