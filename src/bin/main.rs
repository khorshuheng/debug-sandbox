use std::fs;

use serde_json::json;
use yrs::{
  types::ToJson,
  updates::{
    decoder::Decode,
    encoder::{Encode, Encoder, EncoderV1},
  },
  Doc, ReadTxn, StateVector, Transact, Update,
};

fn doc_from_file(input_path: &str) -> Doc {
  let doc_state = fs::read(input_path).unwrap();
  let doc = yrs::Doc::new();
  let update = yrs::Update::decode_v1(&doc_state).unwrap();
  doc.transact_mut().apply_update(update).unwrap();
  doc
}

fn save_as_json(doc: &Doc, output_path: &str) {
  let data_map = doc.get_or_insert_map("data");
  let content = {
    let txn = doc.transact();
    serde_json::to_string_pretty(&json!(data_map.to_json(&txn))).unwrap()
  };
  fs::write(output_path, content).unwrap();
}

fn main() {
  let old_doc = doc_from_file("../../data/old_doc.bin");
  save_as_json(&old_doc, "../../data/old_doc.json");
  let new_doc = doc_from_file("../../data/new_doc.bin");
  save_as_json(&new_doc, "../../data/new_doc.json");

  let encoded_old_doc = old_doc.transact().state_vector().encode_v1();
  let update = {
    let this = &new_doc.transact();
    let state_vector: &StateVector = &StateVector::decode_v1(&encoded_old_doc).unwrap();
    let mut encoder = EncoderV1::new();
    this.encode_diff(state_vector, &mut encoder);
    encoder.to_vec()
  };
  let update = Update::decode_v1(&update).unwrap();
  old_doc.transact_mut().apply_update(update).unwrap();
  save_as_json(&old_doc, "../../data/updated_doc.json");
}
