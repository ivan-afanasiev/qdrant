use std::collections::HashMap;

use segment::data_types::modifier::Modifier as SegmentModifier;
use segment::index::sparse_index::sparse_index_config::{SparseIndexConfig, SparseIndexType as SegmentSparseIndexType};
use segment::types::{
    BinaryQuantization, BinaryQuantizationConfig, BinaryQuantizationEncoding as SegmentBinaryQuantizationEncoding,
    BinaryQuantizationQueryEncoding as SegmentBinaryQuantizationQueryEncoding,
    CompressionRatio as SegmentCompressionRatio, Distance as SegmentDistance,
    Indexes, MultiVectorComparator as SegmentMultiVectorComparator,
    MultiVectorConfig as SegmentMultiVectorConfig, PayloadStorageType,
    ProductQuantization, ProductQuantizationConfig,
    QuantizationConfig as SegmentQuantizationConfig,
    ScalarQuantization, ScalarQuantizationConfig, ScalarType as SegmentScalarType,
    SegmentConfig, SparseVectorDataConfig as SegmentSparseVectorDataConfig,
    SparseVectorStorageType, VectorDataConfig as SegmentVectorDataConfig,
    VectorStorageDatatype as SegmentVectorStorageDatatype, VectorStorageType,
};

// ── Distance ────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum Distance {
    Cosine,
    Euclid,
    Dot,
    Manhattan,
}

impl From<Distance> for SegmentDistance {
    fn from(d: Distance) -> Self {
        match d {
            Distance::Cosine => SegmentDistance::Cosine,
            Distance::Euclid => SegmentDistance::Euclid,
            Distance::Dot => SegmentDistance::Dot,
            Distance::Manhattan => SegmentDistance::Manhattan,
        }
    }
}

impl From<SegmentDistance> for Distance {
    fn from(d: SegmentDistance) -> Self {
        match d {
            SegmentDistance::Cosine => Distance::Cosine,
            SegmentDistance::Euclid => Distance::Euclid,
            SegmentDistance::Dot => Distance::Dot,
            SegmentDistance::Manhattan => Distance::Manhattan,
        }
    }
}

// ── VectorStorageDatatype ───────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum VectorStorageDatatype {
    Float32,
    Float16,
    Uint8,
}

impl From<VectorStorageDatatype> for SegmentVectorStorageDatatype {
    fn from(d: VectorStorageDatatype) -> Self {
        match d {
            VectorStorageDatatype::Float32 => SegmentVectorStorageDatatype::Float32,
            VectorStorageDatatype::Float16 => SegmentVectorStorageDatatype::Float16,
            VectorStorageDatatype::Uint8 => SegmentVectorStorageDatatype::Uint8,
        }
    }
}

impl From<SegmentVectorStorageDatatype> for VectorStorageDatatype {
    fn from(d: SegmentVectorStorageDatatype) -> Self {
        match d {
            SegmentVectorStorageDatatype::Float32 => VectorStorageDatatype::Float32,
            SegmentVectorStorageDatatype::Float16 => VectorStorageDatatype::Float16,
            SegmentVectorStorageDatatype::Uint8 => VectorStorageDatatype::Uint8,
        }
    }
}

// ── MultiVectorComparator ───────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum MultiVectorComparator {
    MaxSim,
}

impl From<MultiVectorComparator> for SegmentMultiVectorComparator {
    fn from(c: MultiVectorComparator) -> Self {
        match c {
            MultiVectorComparator::MaxSim => SegmentMultiVectorComparator::MaxSim,
        }
    }
}

impl From<SegmentMultiVectorComparator> for MultiVectorComparator {
    fn from(c: SegmentMultiVectorComparator) -> Self {
        match c {
            SegmentMultiVectorComparator::MaxSim => MultiVectorComparator::MaxSim,
        }
    }
}

// ── MultiVectorConfig ───────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct MultiVectorConfig {
    pub comparator: MultiVectorComparator,
}

impl From<MultiVectorConfig> for SegmentMultiVectorConfig {
    fn from(c: MultiVectorConfig) -> Self {
        SegmentMultiVectorConfig {
            comparator: SegmentMultiVectorComparator::from(c.comparator),
        }
    }
}

impl From<SegmentMultiVectorConfig> for MultiVectorConfig {
    fn from(c: SegmentMultiVectorConfig) -> Self {
        MultiVectorConfig {
            comparator: MultiVectorComparator::from(c.comparator),
        }
    }
}

// ── ScalarType ──────────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum ScalarType {
    Int8,
}

impl From<ScalarType> for SegmentScalarType {
    fn from(s: ScalarType) -> Self {
        match s {
            ScalarType::Int8 => SegmentScalarType::Int8,
        }
    }
}

impl From<SegmentScalarType> for ScalarType {
    fn from(s: SegmentScalarType) -> Self {
        match s {
            SegmentScalarType::Int8 => ScalarType::Int8,
        }
    }
}

// ── CompressionRatio ────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum CompressionRatio {
    X4,
    X8,
    X16,
    X32,
    X64,
}

impl From<CompressionRatio> for SegmentCompressionRatio {
    fn from(c: CompressionRatio) -> Self {
        match c {
            CompressionRatio::X4 => SegmentCompressionRatio::X4,
            CompressionRatio::X8 => SegmentCompressionRatio::X8,
            CompressionRatio::X16 => SegmentCompressionRatio::X16,
            CompressionRatio::X32 => SegmentCompressionRatio::X32,
            CompressionRatio::X64 => SegmentCompressionRatio::X64,
        }
    }
}

impl From<SegmentCompressionRatio> for CompressionRatio {
    fn from(c: SegmentCompressionRatio) -> Self {
        match c {
            SegmentCompressionRatio::X4 => CompressionRatio::X4,
            SegmentCompressionRatio::X8 => CompressionRatio::X8,
            SegmentCompressionRatio::X16 => CompressionRatio::X16,
            SegmentCompressionRatio::X32 => CompressionRatio::X32,
            SegmentCompressionRatio::X64 => CompressionRatio::X64,
        }
    }
}

// ── BinaryQuantizationEncoding ──────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum BinaryQuantizationEncoding {
    OneBit,
    TwoBits,
    OneAndHalfBits,
}

impl From<BinaryQuantizationEncoding> for SegmentBinaryQuantizationEncoding {
    fn from(e: BinaryQuantizationEncoding) -> Self {
        match e {
            BinaryQuantizationEncoding::OneBit => SegmentBinaryQuantizationEncoding::OneBit,
            BinaryQuantizationEncoding::TwoBits => SegmentBinaryQuantizationEncoding::TwoBits,
            BinaryQuantizationEncoding::OneAndHalfBits => {
                SegmentBinaryQuantizationEncoding::OneAndHalfBits
            }
        }
    }
}

impl From<SegmentBinaryQuantizationEncoding> for BinaryQuantizationEncoding {
    fn from(e: SegmentBinaryQuantizationEncoding) -> Self {
        match e {
            SegmentBinaryQuantizationEncoding::OneBit => BinaryQuantizationEncoding::OneBit,
            SegmentBinaryQuantizationEncoding::TwoBits => BinaryQuantizationEncoding::TwoBits,
            SegmentBinaryQuantizationEncoding::OneAndHalfBits => {
                BinaryQuantizationEncoding::OneAndHalfBits
            }
        }
    }
}

// ── BinaryQuantizationQueryEncoding ─────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum BinaryQuantizationQueryEncoding {
    Default,
    Binary,
    Scalar4Bits,
    Scalar8Bits,
}

impl From<BinaryQuantizationQueryEncoding> for SegmentBinaryQuantizationQueryEncoding {
    fn from(e: BinaryQuantizationQueryEncoding) -> Self {
        match e {
            BinaryQuantizationQueryEncoding::Default => SegmentBinaryQuantizationQueryEncoding::Default,
            BinaryQuantizationQueryEncoding::Binary => SegmentBinaryQuantizationQueryEncoding::Binary,
            BinaryQuantizationQueryEncoding::Scalar4Bits => SegmentBinaryQuantizationQueryEncoding::Scalar4Bits,
            BinaryQuantizationQueryEncoding::Scalar8Bits => SegmentBinaryQuantizationQueryEncoding::Scalar8Bits,
        }
    }
}

impl From<SegmentBinaryQuantizationQueryEncoding> for BinaryQuantizationQueryEncoding {
    fn from(e: SegmentBinaryQuantizationQueryEncoding) -> Self {
        match e {
            SegmentBinaryQuantizationQueryEncoding::Default => BinaryQuantizationQueryEncoding::Default,
            SegmentBinaryQuantizationQueryEncoding::Binary => BinaryQuantizationQueryEncoding::Binary,
            SegmentBinaryQuantizationQueryEncoding::Scalar4Bits => BinaryQuantizationQueryEncoding::Scalar4Bits,
            SegmentBinaryQuantizationQueryEncoding::Scalar8Bits => BinaryQuantizationQueryEncoding::Scalar8Bits,
        }
    }
}

// ── Quantization configs ────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct ScalarQuantizationParams {
    pub r#type: ScalarType,
    pub quantile: Option<f32>,
    pub always_ram: Option<bool>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct ProductQuantizationParams {
    pub compression: CompressionRatio,
    pub always_ram: Option<bool>,
}

#[derive(Clone, Debug, uniffi::Record)]
pub struct BinaryQuantizationParams {
    pub always_ram: Option<bool>,
    pub encoding: Option<BinaryQuantizationEncoding>,
    pub query_encoding: Option<BinaryQuantizationQueryEncoding>,
}

#[derive(Clone, Debug, uniffi::Enum)]
pub enum QuantizationConfig {
    Scalar { config: ScalarQuantizationParams },
    Product { config: ProductQuantizationParams },
    Binary { config: BinaryQuantizationParams },
}

impl From<QuantizationConfig> for SegmentQuantizationConfig {
    fn from(c: QuantizationConfig) -> Self {
        match c {
            QuantizationConfig::Scalar { config } => {
                SegmentQuantizationConfig::Scalar(ScalarQuantization {
                    scalar: ScalarQuantizationConfig {
                        r#type: SegmentScalarType::from(config.r#type),
                        quantile: config.quantile,
                        always_ram: config.always_ram,
                    },
                })
            }
            QuantizationConfig::Product { config } => {
                SegmentQuantizationConfig::Product(ProductQuantization {
                    product: ProductQuantizationConfig {
                        compression: SegmentCompressionRatio::from(config.compression),
                        always_ram: config.always_ram,
                    },
                })
            }
            QuantizationConfig::Binary { config } => {
                SegmentQuantizationConfig::Binary(BinaryQuantization {
                    binary: BinaryQuantizationConfig {
                        always_ram: config.always_ram,
                        encoding: config.encoding.map(SegmentBinaryQuantizationEncoding::from),
                        query_encoding: config
                            .query_encoding
                            .map(SegmentBinaryQuantizationQueryEncoding::from),
                    },
                })
            }
        }
    }
}

impl From<SegmentQuantizationConfig> for QuantizationConfig {
    fn from(c: SegmentQuantizationConfig) -> Self {
        match c {
            SegmentQuantizationConfig::Scalar(ScalarQuantization { scalar }) => {
                QuantizationConfig::Scalar {
                    config: ScalarQuantizationParams {
                        r#type: ScalarType::from(scalar.r#type),
                        quantile: scalar.quantile,
                        always_ram: scalar.always_ram,
                    },
                }
            }
            SegmentQuantizationConfig::Product(ProductQuantization { product }) => {
                QuantizationConfig::Product {
                    config: ProductQuantizationParams {
                        compression: CompressionRatio::from(product.compression),
                        always_ram: product.always_ram,
                    },
                }
            }
            SegmentQuantizationConfig::Binary(BinaryQuantization { binary }) => {
                QuantizationConfig::Binary {
                    config: BinaryQuantizationParams {
                        always_ram: binary.always_ram,
                        encoding: binary.encoding.map(BinaryQuantizationEncoding::from),
                        query_encoding: binary
                            .query_encoding
                            .map(BinaryQuantizationQueryEncoding::from),
                    },
                }
            }
        }
    }
}

// ── VectorDataConfig ────────────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct VectorDataConfig {
    pub size: u64,
    pub distance: Distance,
    pub quantization_config: Option<QuantizationConfig>,
    pub multivector_config: Option<MultiVectorConfig>,
    pub datatype: Option<VectorStorageDatatype>,
}

impl From<VectorDataConfig> for SegmentVectorDataConfig {
    fn from(c: VectorDataConfig) -> Self {
        SegmentVectorDataConfig {
            size: c.size as usize,
            distance: SegmentDistance::from(c.distance),
            storage_type: VectorStorageType::InRamChunkedMmap,
            index: Indexes::Plain {},
            quantization_config: c.quantization_config.map(SegmentQuantizationConfig::from),
            multivector_config: c.multivector_config.map(SegmentMultiVectorConfig::from),
            datatype: c.datatype.map(SegmentVectorStorageDatatype::from),
        }
    }
}

impl From<SegmentVectorDataConfig> for VectorDataConfig {
    fn from(c: SegmentVectorDataConfig) -> Self {
        VectorDataConfig {
            size: c.size as u64,
            distance: Distance::from(c.distance),
            quantization_config: c.quantization_config.map(QuantizationConfig::from),
            multivector_config: c.multivector_config.map(MultiVectorConfig::from),
            datatype: c.datatype.map(VectorStorageDatatype::from),
        }
    }
}

// ── SparseIndexType ─────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum SparseIndexType {
    MutableRam,
    ImmutableRam,
    Mmap,
}

impl From<SparseIndexType> for SegmentSparseIndexType {
    fn from(t: SparseIndexType) -> Self {
        match t {
            SparseIndexType::MutableRam => SegmentSparseIndexType::MutableRam,
            SparseIndexType::ImmutableRam => SegmentSparseIndexType::ImmutableRam,
            SparseIndexType::Mmap => SegmentSparseIndexType::Mmap,
        }
    }
}

impl From<SegmentSparseIndexType> for SparseIndexType {
    fn from(t: SegmentSparseIndexType) -> Self {
        match t {
            SegmentSparseIndexType::MutableRam => SparseIndexType::MutableRam,
            SegmentSparseIndexType::ImmutableRam => SparseIndexType::ImmutableRam,
            SegmentSparseIndexType::Mmap => SparseIndexType::Mmap,
        }
    }
}

// ── Modifier ────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum Modifier {
    None,
    Idf,
}

impl From<Modifier> for SegmentModifier {
    fn from(m: Modifier) -> Self {
        match m {
            Modifier::None => SegmentModifier::None,
            Modifier::Idf => SegmentModifier::Idf,
        }
    }
}

impl From<SegmentModifier> for Modifier {
    fn from(m: SegmentModifier) -> Self {
        match m {
            SegmentModifier::None => Modifier::None,
            SegmentModifier::Idf => Modifier::Idf,
        }
    }
}

// ── SparseVectorDataConfig ──────────────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct SparseVectorDataConfig {
    pub full_scan_threshold: Option<u64>,
    pub datatype: Option<VectorStorageDatatype>,
    pub modifier: Option<Modifier>,
}

impl From<SparseVectorDataConfig> for SegmentSparseVectorDataConfig {
    fn from(c: SparseVectorDataConfig) -> Self {
        SegmentSparseVectorDataConfig {
            index: SparseIndexConfig {
                index_type: SegmentSparseIndexType::MutableRam,
                full_scan_threshold: c.full_scan_threshold.map(|v| v as usize),
                datatype: c.datatype.map(SegmentVectorStorageDatatype::from),
            },
            storage_type: SparseVectorStorageType::Mmap,
            modifier: c.modifier.map(SegmentModifier::from),
        }
    }
}

impl From<SegmentSparseVectorDataConfig> for SparseVectorDataConfig {
    fn from(c: SegmentSparseVectorDataConfig) -> Self {
        SparseVectorDataConfig {
            full_scan_threshold: c.index.full_scan_threshold.map(|v| v as u64),
            datatype: c.index.datatype.map(VectorStorageDatatype::from),
            modifier: c.modifier.map(Modifier::from),
        }
    }
}

// ── EdgeConfig (wraps SegmentConfig) ────────────────────────────────────────

#[derive(Clone, Debug, uniffi::Record)]
pub struct EdgeConfig {
    pub vector_data: HashMap<String, VectorDataConfig>,
    pub sparse_vector_data: HashMap<String, SparseVectorDataConfig>,
}

impl From<EdgeConfig> for SegmentConfig {
    fn from(c: EdgeConfig) -> Self {
        SegmentConfig {
            vector_data: c
                .vector_data
                .into_iter()
                .map(|(k, v)| (k, SegmentVectorDataConfig::from(v)))
                .collect(),
            sparse_vector_data: c
                .sparse_vector_data
                .into_iter()
                .map(|(k, v)| (k, SegmentSparseVectorDataConfig::from(v)))
                .collect(),
            payload_storage_type: PayloadStorageType::Mmap,
        }
    }
}

impl From<SegmentConfig> for EdgeConfig {
    fn from(c: SegmentConfig) -> Self {
        EdgeConfig {
            vector_data: c
                .vector_data
                .into_iter()
                .map(|(k, v)| (k, VectorDataConfig::from(v)))
                .collect(),
            sparse_vector_data: c
                .sparse_vector_data
                .into_iter()
                .map(|(k, v)| (k, SparseVectorDataConfig::from(v)))
                .collect(),
        }
    }
}
