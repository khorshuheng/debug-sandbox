use serde::Deserialize;
use serde_json::json;
use tokio::fs;
use yrs::{
  types::ToJson,
  updates::{decoder::Decode, encoder::Encode},
  Doc, ReadTxn, StateVector, Transact, Update,
};

static BASE_URL: &str = "https://beta.appflowy.cloud";

#[derive(Deserialize)]
struct UserProfile {
  pub uid: i64,
}

#[derive(Deserialize)]
struct UserProfileResp {
  pub data: UserProfile,
}

#[derive(Deserialize)]
struct DocState {
  pub doc_state: Vec<u8>,
}

#[derive(Deserialize)]
struct GetCollabResp {
  pub data: DocState,
}

async fn get_user_id(token: &str) -> i64 {
  let client = reqwest::Client::new();
  let resp = client
    .get(get_user_profile_endpoint())
    .bearer_auth(token)
    .send()
    .await
    .unwrap();
  assert!(resp.status().is_success());
  let user_profile: UserProfileResp = resp.json().await.unwrap();
  user_profile.data.uid
}

async fn get_document(token: &str, workspace_id: &str, collab_id: &str) -> Doc {
  let client = reqwest::Client::new();
  let resp = client
    .get(v1_collab_endpoint(workspace_id, collab_id))
    .query(&[("collab_type", 0)])
    .bearer_auth(token)
    .send()
    .await
    .unwrap();
  assert!(resp.status().is_success());
  let document_resp: GetCollabResp = resp.json().await.unwrap();
  let doc_state = document_resp.data.doc_state;
  fs::write("../../data/new_doc.bin", doc_state.clone())
    .await
    .unwrap();
  let doc = yrs::Doc::new();
  let update = yrs::Update::decode_v1(&doc_state).unwrap();
  doc.transact_mut().apply_update(update).unwrap();
  let data_map = doc.get_or_insert_map("data");
  let content = {
    let txn = doc.transact();
    serde_json::to_string_pretty(&json!(data_map.to_json(&txn))).unwrap()
  };
  fs::write("../../data/document.json", content)
    .await
    .unwrap();
  doc
}

async fn get_published_document(token: &str, workspace_id: &str, collab_id: &str) -> Doc {
  let client = reqwest::Client::new();
  let endpoint = published_document_endpoint(workspace_id, collab_id);
  let resp = client
    .get(endpoint)
    .bearer_auth(token)
    .send()
    .await
    .unwrap();
  assert!(resp.status().is_success());
  let doc_state = resp.bytes().await.unwrap();
  fs::write("../../data/old_doc.bin", doc_state.clone())
    .await
    .unwrap();
  let doc = yrs::Doc::new();
  let update = yrs::Update::decode_v1(&doc_state).unwrap();
  doc.transact_mut().apply_update(update).unwrap();
  let data_map = doc.get_or_insert_map("data");
  let content = {
    let txn = doc.transact();
    serde_json::to_string_pretty(&json!(data_map.to_json(&txn))).unwrap()
  };
  doc
  // fs::write("published.json", content).await.unwrap();
}

fn get_user_profile_endpoint() -> String {
  api_endpoint("user/profile")
}

fn v1_collab_endpoint(workspace_id: &str, collab_id: &str) -> String {
  api_endpoint(&format!(
    "workspace/v1/{}/collab/{}",
    workspace_id, collab_id
  ))
}

fn published_document_endpoint(namespace: &str, name: &str) -> String {
  api_endpoint(&format!("workspace/published/{namespace}/{name}/blob"))
}

fn api_endpoint(path: &str) -> String {
  format!("{}/api/{}", BASE_URL, path)
}

fn gotrue_endpoint(path: &str) -> String {
  format!("{}/gotrue/{}", BASE_URL, path)
}

#[derive(Deserialize, Debug)]
struct TokenResponse {
  access_token: String,
}

async fn get_access_token(email: &str, password: &str) -> String {
  let client = reqwest::Client::new();
  let resp = client
    .post(gotrue_endpoint("token"))
    .json(&json!({
      "email": email,
      "password": password,
    }))
    .query(&[("grant_type", "password")])
    .send()
    .await
    .unwrap();
  let token_resp: TokenResponse = resp.json().await.unwrap();
  token_resp.access_token
}

#[tokio::main]
async fn main() {
  let email = "shuheng@appflowy.io";
  let password = "#7thHeaven#";
  let token = get_access_token(email, password).await;
  let workspace_id = "9c8084ae-447d-4747-a213-ce3a21ab7ae9";
  let collab_id = "ac4de83a-35c0-43db-81f5-fc077ff1925b";
  let namespace = "a2b56e70-959b-4471-a628-35b530d6bfb0";
  let name = "err-msg-ac4de83a-35c0-43db-81f5-fc077ff1925b";
  let app_doc = get_document(&token, workspace_id, collab_id).await;
  let published_doc = get_published_document(&token, namespace, name).await;
  let encoded_published_doc = published_doc.transact().state_vector().encode_v1();
  let update = app_doc
    .transact()
    .encode_diff_v1(&StateVector::decode_v1(&encoded_published_doc).unwrap());
  let update = Update::decode_v1(&update).unwrap();
  println!("{:?}", update);
  published_doc.transact_mut().apply_update(update).unwrap();
  let data_map = published_doc.get_or_insert_map("data");
  let content = {
    let txn = published_doc.transact();
    serde_json::to_string_pretty(&json!(data_map.to_json(&txn))).unwrap()
  };
  fs::write("updated_published_1.json", content)
    .await
    .unwrap();
}
